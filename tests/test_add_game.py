import binascii
import importlib.machinery
import importlib.util
import io
import os
import struct
import tempfile
import unittest
from contextlib import redirect_stdout

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(env):
    os.environ.update(env)
    loader = importlib.machinery.SourceFileLoader("add_game", os.path.join(ROOT, "resources/add-game"))
    spec = importlib.util.spec_from_loader("add_game", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def write(path, text, mode="w"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, mode) as f:
        f.write(text)


def acf(appid, name, installdir, flags=4):
    return ('"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"StateFlags"\t\t"%d"\n'
            '\t"installdir"\t\t"%s"\n}\n' % (appid, name, flags, installdir))


class AddGameTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.bottle = os.path.join(t, "Bottles/Steam")
        self.macsteam = os.path.join(t, "MacSteam")
        self.launcher = "/Applications/Console Mode.app/Contents/Resources/bottle-launch"
        os.makedirs(os.path.join(self.macsteam, "userdata/12345/config"))
        steam = os.path.join(self.bottle, "drive_c/Program Files (x86)/Steam")
        # Library on D: (the games drive), mapped via dosdevices.
        games_drive = os.path.join(t, "circular")
        os.makedirs(os.path.join(self.bottle, "dosdevices"))
        os.symlink(games_drive, os.path.join(self.bottle, "dosdevices/d:"))
        write(os.path.join(steam, "steamapps/libraryfolders.vdf"),
              '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"\n\t}\n'
              '\t"1"\n\t{\n\t\t"path"\t\t"D:\\\\SteamLibrary"\n\t}\n}\n')
        write(os.path.join(steam, "steamapps/appmanifest_1091500.acf"), acf(1091500, "Cyberpunk 2077", "Cyberpunk 2077"))
        write(os.path.join(steam, "steamapps/appmanifest_228980.acf"), acf(228980, "Steamworks Common Redistributables", "x"))
        write(os.path.join(games_drive, "SteamLibrary/steamapps/appmanifest_620.acf"), acf(620, "Portal 2", "Portal 2"))
        write(os.path.join(games_drive, "SteamLibrary/steamapps/appmanifest_999.acf"), acf(999, "Half Downloaded", "hd", flags=1026 & ~4))
        write(os.path.join(steam, "appcache/librarycache/620/abc123/library_600x900.jpg"), "portrait")
        write(os.path.join(steam, "appcache/librarycache/620/library_hero.jpg"), "hero")
        write(os.path.join(steam, "appcache/librarycache/1091500_header.jpg"), "oldlayout")
        self.m = load({"CM_BOTTLE": self.bottle, "CM_MAC_STEAM": self.macsteam,
                       "CM_LAUNCHER": self.launcher, "CM_ASSUME_STEAM_CLOSED": "1"})

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = self.m.main(list(args))
        return rc, buf.getvalue()

    # --- format

    def test_vdf_roundtrip_and_layout(self):
        e = self.m.make_entry("Game", "steam", "620")
        data = self.m.vdf_dump({"shortcuts": {"0": e}})
        self.assertTrue(data.startswith(b"\x00shortcuts\x00\x000\x00"))
        self.assertTrue(data.endswith(b"\x08\x08\x08"))  # tags, entry... + root
        self.assertEqual(self.m.vdf_load(data), {"shortcuts": {"0": e}})

    def test_appid_formula(self):
        e = self.m.make_entry("Portal 2", "steam", "620")
        expect = (binascii.crc32(('"%s"Portal 2' % self.launcher).encode()) & 0xFFFFFFFF) | 0x80000000
        self.assertEqual(self.m.unsigned_appid(e), expect)
        self.assertLess(e["appid"], 0)  # stored as signed int32 like Steam does
        packed = self.m.vdf_dump({"x": {"appid": e["appid"]}})
        self.assertIn(struct.pack("<I", expect), packed)

    def test_text_vdf(self):
        d = self.m.text_vdf('"A" { "b" "c\\\\d" "E" { } }')
        self.assertEqual(d, {"A": {"b": "c\\d", "E": {}}})

    # --- add / list / remove

    def test_add_list_remove(self):
        rc, _ = self.run_cli("Portal 2", "steam", "620")
        self.assertEqual(rc, 0)
        exe = os.path.join(self.tmp.name, "game.exe")
        write(exe, "MZ")
        self.run_cli("My Game", "exe", exe)
        _, out = self.run_cli("--list")
        self.assertIn("Portal 2", out)
        self.assertIn('exe "%s"' % exe, out)
        self.run_cli("--remove", "Portal 2")
        _, out = self.run_cli("--list")
        self.assertNotIn("Portal 2", out)
        self.assertIn("My Game", out)

    def test_re_adding_replaces(self):
        self.run_cli("Portal 2", "steam", "620")
        self.run_cli("Portal 2", "steam", "620")
        self.assertEqual(len(self.m.load_shortcuts()), 1)

    def test_bad_args(self):
        with self.assertRaises(SystemExit):
            self.m.main(["X", "steam", "abc"])
        with self.assertRaises(SystemExit):
            self.m.main(["X", "exe", "/nope.exe"])

    def test_refuses_while_steam_runs(self):
        os.environ["CM_ASSUME_STEAM_CLOSED"] = "0"
        self.m.mac_steam_running = lambda: True
        with self.assertRaises(SystemExit):
            self.m.main(["Portal 2", "steam", "620"])
        os.environ["CM_ASSUME_STEAM_CLOSED"] = "1"

    def test_preserves_foreign_entries(self):
        foreign = {"appid": -5, "AppName": "Emulator", "Exe": '"/Applications/Emu.app"',
                   "LaunchOptions": "", "tags": {"0": "favorite"}}
        self.m.save_shortcuts([foreign])
        self.run_cli("--sync")
        names = [e["AppName"] for e in self.m.load_shortcuts()]
        self.assertIn("Emulator", names)
        self.assertEqual(self.m.load_shortcuts()[0], foreign)

    # --- sync

    def test_installed_games_skip_redist_and_partial(self):
        names = [g[1] for g in self.m.installed_bottle_games()]
        self.assertEqual(names, ["Cyberpunk 2077", "Portal 2"])

    def test_check_then_sync_then_check(self):
        rc, out = self.run_cli("--check")
        self.assertEqual(rc, 10)
        self.assertIn("+ Portal 2", out)
        rc, _ = self.run_cli("--sync")
        self.assertEqual(rc, 0)
        rc, _ = self.run_cli("--check")
        self.assertEqual(rc, 0)
        tags = {e["AppName"]: self.m.entry_tags(e) for e in self.m.load_shortcuts()}
        self.assertEqual(tags["Portal 2"], ["Bottle Steam"])

    def test_sync_copies_art(self):
        self.run_cli("--sync")
        ids = {e["AppName"]: self.m.unsigned_appid(e) for e in self.m.load_shortcuts()}
        grid = os.path.join(self.macsteam, "userdata/12345/config/grid")
        with open(os.path.join(grid, "%dp.jpg" % ids["Portal 2"])) as f:
            self.assertEqual(f.read(), "portrait")
        self.assertTrue(os.path.exists(os.path.join(grid, "%d_hero.jpg" % ids["Portal 2"])))
        with open(os.path.join(grid, "%d.jpg" % ids["Cyberpunk 2077"])) as f:
            self.assertEqual(f.read(), "oldlayout")

    def test_sync_removes_uninstalled(self):
        self.run_cli("--sync")
        os.remove(os.path.join(self.tmp.name, "circular/SteamLibrary/steamapps/appmanifest_620.acf"))
        rc, out = self.run_cli("--check")
        self.assertEqual(rc, 10)
        self.assertIn("- Portal 2", out)
        self.run_cli("--sync")
        self.assertEqual([e["AppName"] for e in self.m.load_shortcuts()], ["Cyberpunk 2077"])

    def test_sync_does_not_duplicate_manual_tile(self):
        self.run_cli("Portal 2", "steam", "620")      # user-made, untagged
        self.run_cli("--sync")
        names = [e["AppName"] for e in self.m.load_shortcuts()]
        self.assertEqual(names.count("Portal 2"), 1)


if __name__ == "__main__":
    unittest.main()
