#!/bin/zsh
# Builds "Console Mode.app" and installs it to /Applications.
#   ./build.sh              build + install
#   ./build.sh --no-install build into ./build only (used by CI)
emulate -L zsh
setopt err_exit pipe_fail

here=${0:A:h}
app_name="Console Mode"
build=$here/build
app=$build/$app_name.app
install=1
[[ ${1:-} == --no-install ]] && install=0

arch=$(uname -m)
target=$arch-apple-macos15.0
swiftc_flags=(-O -swift-version 5 -target $target)

print "==> compiling ($target)"
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
swiftc $swiftc_flags -o $app/Contents/MacOS/ConsoleMode $here/src/*.swift \
  -framework AppKit -framework SwiftUI -framework GameController -framework IOKit
swiftc $swiftc_flags -o $app/Contents/Resources/bottle-windows $here/resources/bottle-windows.swift

print "==> bundling"
cp $here/resources/Info.plist $app/Contents/Info.plist
for f in bottle-launch add-game backup-saves watchdog; do
  cp $here/resources/$f $app/Contents/Resources/$f
  chmod +x $app/Contents/Resources/$f
done

# Ad-hoc signing normally keys privacy permissions (TCC) on the code hash, so
# every rebuild would lose Screen Recording. A designated requirement on the
# bundle id keeps permissions across rebuilds.
print "==> signing"
codesign --force --deep --sign - \
  -r='designated => identifier "local.consolemode"' $app
codesign --verify --strict $app

if (( install )); then
  print "==> installing to /Applications"
  pkill -x ConsoleMode 2>/dev/null || true
  rm -rf "/Applications/$app_name.app"
  cp -R $app /Applications/
  print "Installed /Applications/$app_name.app"
else
  print "Built $app"
fi
