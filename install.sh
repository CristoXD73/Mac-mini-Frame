#!/bin/bash
# Put `steam-tune` on your PATH by symlinking it into ~/.local/bin (or $1).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
dest="${1:-$HOME/.local/bin}"
mkdir -p "$dest"
chmod +x "$here/bin/steam-tune" "$here"/macos/*.command
ln -sf "$here/bin/steam-tune" "$dest/steam-tune"
echo "Installed: $dest/steam-tune -> $here/bin/steam-tune"
case ":$PATH:" in
  *":$dest:"*) ;;
  *) echo "Add it to your PATH:  echo 'export PATH=\"$dest:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
esac
