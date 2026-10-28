#!/usr/bin/env bash
# Install the AppArmor profile that lets codex's bubblewrap sandbox run
# inside the app (see scripts/apparmor/alcfai-app). Needs sudo.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
sudo install -m 644 "$here/apparmor/alcfai-app" /etc/apparmor.d/alcfai-app
sudo apparmor_parser -r /etc/apparmor.d/alcfai-app
echo "Profile loaded. Restart ALCF AI."
