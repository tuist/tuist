#!/usr/bin/env bash
# Per-user installation. Run explicitly to make this app the tuist: handler.
set -euo pipefail

source_binary=${1:?Usage: install-linux.sh /path/to/TuistCode}
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
install_dir="$data_home/tuist-code"
applications="$data_home/applications"
mkdir -p "$install_dir" "$applications"
install -m 755 "$source_binary" "$install_dir/TuistCode"

# Desktop Entry Exec quoting is not shell quoting; literal percent signs must
# be doubled as well as escaping reserved characters inside a quoted argument.
executable=$(printf '%s' "$install_dir/TuistCode" | sed 's/[\\"`$]/\\&/g; s/%/%%/g; s/\\/\\\\/g')
cat > "$applications/dev.tuist.code.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Tuist Code
Comment=Tuist Code
Exec="$executable" %u
Terminal=false
Categories=Development;
MimeType=x-scheme-handler/tuist;
StartupWMClass=dev.tuist.code
EOF
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$applications"
fi
xdg-mime default dev.tuist.code.desktop x-scheme-handler/tuist
printf 'Installed Tuist in %s and registered tuist: links.\n' "$install_dir"
