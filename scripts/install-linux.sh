#!/usr/bin/env bash
# Build and install ALCF AI for the current user.
#
#   scripts/install-linux.sh            # flutter build linux --release, then install
#   scripts/install-linux.sh --no-build # install the existing release bundle
#
# Safe to run again to update: the app directory is replaced; the app's own
# folder (~/.local/share/alcfai/home) is not touched.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
flutter="${FLUTTER:-$HOME/Software/flutter/bin/flutter}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$HOME/.local/opt/alcfai-app"
apps="$data/applications"
hicolor="$data/icons/hicolor"
app_id="dev.ravoux.alcfai_app"
src="$here/build/linux/x64/release/bundle"

if [[ "${1:-}" != "--no-build" ]]; then
  (cd "$here" && "$flutter" build linux --release)
fi
if [[ ! -x "$src/alcfai_app" ]]; then
  echo "No release bundle at $src. Build it with: flutter build linux --release" >&2
  exit 1
fi

mkdir -p "$(dirname "$dest")" "$apps" "$hicolor/512x512/apps" "$hicolor/scalable/apps"
rm -rf "$dest.new"
cp -a "$src" "$dest.new"
rm -rf "$dest"
mv "$dest.new" "$dest"

cp "$here/assets/icon/alcfai.png" "$hicolor/512x512/apps/$app_id.png"
cp "$here/assets/icon/alcfai.svg" "$hicolor/scalable/apps/$app_id.svg"

# Named after the application id, which GNOME uses to match the window.
cat > "$apps/$app_id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=ALCF AI
Comment=Coding agents on ALCF inference, without touching your Claude setup
Exec=$dest/alcfai_app
Icon=$app_id
Terminal=false
Categories=Development;
StartupWMClass=$app_id
DESKTOP

update-desktop-database "$apps" >/dev/null 2>&1 || true
gtk-update-icon-cache -q -t "$hicolor" >/dev/null 2>&1 || true
echo "Installed to $dest. Launch ALCF AI from the applications menu."
