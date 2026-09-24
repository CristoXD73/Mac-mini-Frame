import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import time
import unittest
from contextlib import redirect_stdout

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(env):
    os.environ.update(env)
    loader = importlib.machinery.SourceFileLoader("backup_saves", os.path.join(ROOT, "resources/backup-saves"))
    spec = importlib.util.spec_from_loader("backup_saves", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def write(path, text="x", mtime=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    if mtime is not None:
        os.utime(path, (mtime, mtime))


def tree_digest(path):
    """Content + mtime + mode of every file, to prove sources are untouched."""
    h = hashlib.sha256()
    for root, dirs, files in os.walk(path):
        dirs.sort()
        for n in sorted(files):
            p = os.path.join(root, n)
            st = os.stat(p)
            with open(p, "rb") as f:
                h.update(p.encode() + f.read() + str((st.st_mtime, st.st_mode)).encode())
    return h.hexdigest()


class BackupSavesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.home = os.path.join(t, "home")
        self.bottle = os.path.join(t, "Bottles/Steam")
        self.dest = os.path.join(t, "dest")
        u = os.path.join(self.bottle, "drive_c/users/crossover")
        self.old = time.time() - 86400
        self.since = time.time() - 600
        # Changed this session:
        write(os.path.join(u, "Saved Games/CD Projekt Red/Cyberpunk 2077/save1/sav.dat"), "S1")
        write(os.path.join(u, "Saved Games/CD Projekt Red/Cyberpunk 2077/save1/debug.log"), "noise")
        write(os.path.join(u, "AppData/Local/CD Projekt Red/Cyberpunk 2077/UserSettings.json"), "{}")
        write(os.path.join(u, "AppData/Local/CD Projekt Red/Cyberpunk 2077/cache/big.bin"), "junk")
        write(os.path.join(u, "AppData/Local/Temp/whatever/tmp.bin"), "junk")
        write(os.path.join(u, "AppData/Local/Microsoft/Windows/x.dat"), "junk")
        write(os.path.join(self.home, "Documents/My Games/Skyrim/Saves/a.ess"), "E")
        write(os.path.join(self.home, "Documents/claude/project/notes.md"), "not a save")
        write(os.path.join(self.bottle, "drive_c/Program Files (x86)/Steam/userdata/42/620/remote/p2.sav"), "P")
        write(os.path.join(self.bottle, "drive_c/Program Files (x86)/Steam/userdata/42/7/remote/cfg"), "steam")
        # Not changed this session:
        write(os.path.join(u, "Saved Games/Old Vendor/Old Game/s.dat"), "old", mtime=self.old)
        self.m = load({"CM_HOME": self.home, "CM_BOTTLE": self.bottle, "CM_BACKUP_DEST": self.dest})
        self.m.DEST = self.dest

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = self.m.main(list(args))
        return rc, buf.getvalue()

    def folders(self):
        return sorted(os.listdir(self.dest)) if os.path.isdir(self.dest) else []

    def test_dry_run_finds_expected_and_writes_nothing(self):
        rc, out = self.run_cli("--since", str(self.since), "--dry-run")
        self.assertEqual(rc, 0)
        self.assertIn("Saved Games/CD Projekt Red/Cyberpunk 2077", out)
        self.assertIn("AppData/Local/CD Projekt Red/Cyberpunk 2077", out)
        self.assertIn("My Games/Skyrim", out)
        self.assertIn("userdata/42/620/remote", out)
        for bad in ("Old Game", "Temp", "Microsoft", "claude", "/7/remote"):
            self.assertNotIn(bad, out)
        self.assertEqual(self.folders(), [])

    def test_backup_contents_and_manifest(self):
        before = tree_digest(self.bottle) + tree_digest(self.home)
        self.run_cli("--since", str(self.since), "--label", "Cyberpunk2077.exe")
        self.assertEqual(before, tree_digest(self.bottle) + tree_digest(self.home),
                         "sources must never change")
        self.assertIn("Saved Games - CD Projekt Red - Cyberpunk 2077", self.folders())
        self.assertIn("Steam Cloud - 42 - 620", self.folders())
        folder = os.path.join(self.dest, "Saved Games - CD Projekt Red - Cyberpunk 2077")
        (stamp,) = os.listdir(folder)
        self.assertRegex(stamp, r"^\d{4}-\d\d-\d\d \d\d-\d\d-\d\d$")
        b = os.path.join(folder, stamp)
        with open(os.path.join(b, "save1/sav.dat")) as f:
            self.assertEqual(f.read(), "S1")
        self.assertFalse(os.path.exists(os.path.join(b, "save1/debug.log")))
        with open(os.path.join(b, ".manifest.json")) as f:
            man = json.load(f)
        self.assertEqual(man["label"], "Cyberpunk2077.exe")
        self.assertEqual([x["path"] for x in man["files"]], ["save1/sav.dat"])
        local = os.path.join(self.dest, "AppData Local - CD Projekt Red - Cyberpunk 2077")
        (stamp2,) = os.listdir(local)
        self.assertFalse(os.path.exists(os.path.join(local, stamp2, "cache")))

    def test_no_duplicate_when_unchanged(self):
        self.run_cli("--since", str(self.since))
        _, out = self.run_cli("--since", str(self.since))
        self.assertIn("unchanged since last backup", out)
        folder = os.path.join(self.dest, "My Games - Skyrim")
        self.assertEqual(len(os.listdir(folder)), 1)

    def test_keeps_newest_15(self):
        folder = os.path.join(self.dest, "My Games - Skyrim")
        for i in range(20):
            os.makedirs(os.path.join(folder, "2020-01-01 00-00-%02d" % i))
        self.run_cli("--since", str(self.since))
        stamps = sorted(os.listdir(folder))
        self.assertEqual(len(stamps), 15)
        self.assertNotIn("2020-01-01 00-00-00", stamps)

    def test_size_limit(self):
        self.m.MAX_FILES = 0
        _, out = self.run_cli("--since", str(self.since), "--dry-run")
        self.assertIn("skip (over", out)

    def test_failed_verification_leaves_no_backup(self):
        real = self.m.shutil.copyfileobj
        self.m.shutil.copyfileobj = lambda fi, fo, n=0: fo.write(b"")  # truncated copy
        try:
            self.run_cli("--since", str(self.since))
        finally:
            self.m.shutil.copyfileobj = real
        folder = os.path.join(self.dest, "My Games - Skyrim")
        self.assertEqual(os.listdir(folder), [])  # no stamp, no .incoming left behind


if __name__ == "__main__":
    unittest.main()
