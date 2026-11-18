#!/bin/bash
#
# Adds KuKu Project Checker to the desktop's application menu, with its icon.
# Build the app first: flutter build linux --release
#
set -e

APP_ID=org.elkuku.kuku_project_checker
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BINARY="$DIR/build/linux/x64/release/bundle/kuku_project_checker"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ ! -x "$BINARY" ]; then
  echo "❌ $BINARY not found. Run: flutter build linux --release"
  exit 1
fi

install -Dm644 "$DIR/linux/packaging/$APP_ID.svg" "$DATA/icons/hicolor/scalable/apps/$APP_ID.svg"

# The file name matches the app ID, so the desktop also uses the icon for the open window.
install -d "$DATA/applications"
cat > "$DATA/applications/$APP_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=KuKu Project Checker
GenericName=Project Checker
Comment=Check the Symfony sites and their local git repositories
Exec=$BINARY
Icon=$APP_ID
Terminal=false
Categories=Development;
Keywords=symfony;php;git;deploy;
StartupWMClass=$APP_ID
DESKTOP

# Refresh the menu.
command -v update-desktop-database >/dev/null && update-desktop-database "$DATA/applications" || true
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$DATA/icons/hicolor" 2>/dev/null || true

echo "✅ Added \"KuKu Project Checker\" to the application menu."
