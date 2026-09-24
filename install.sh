#!/bin/bash
# Put `mac-mini-frame` on your PATH by symlinking it into ~/.local/bin (or $1).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
dest="${1:-$HOME/.local/bin}"
mkdir -p "$dest"
chmod +x "$here/bin/mac-mini-frame" "$here"/macos/*.command
ln -sf "$here/bin/mac-mini-frame" "$dest/mac-mini-frame"
echo "Installed: $dest/mac-mini-frame -> $here/bin/mac-mini-frame"
case ":$PATH:" in
  *":$dest:"*) ;;
  *) echo "Add it to your PATH:  echo 'export PATH=\"$dest:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
esac
