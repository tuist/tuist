#!/usr/bin/env bash
# Per-user installation. Run explicitly to make this app the tuist: handler.
set -euo pipefail

source_binary=${1:?Usage: install-linux.sh /path/to/Luft}
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
install_dir="$data_home/luft"
applications="$data_home/applications"
mkdir -p "$install_dir" "$applications"
install -m 755 "$source_binary" "$install_dir/Luft"

# Desktop Entry Exec quoting is not shell quoting; literal percent signs must
# be doubled as well as escaping reserved characters inside a quoted argument.
executable=$(printf '%s' "$install_dir/Luft" | sed 's/[\\"`$]/\\&/g; s/%/%%/g; s/\\/\\\\/g')
cat > "$applications/dev.tuist.guild.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Luft
Comment=Luft
Exec="$executable" %u
Terminal=false
Categories=Development;
MimeType=x-scheme-handler/tuist;x-scheme-handler/luft;
StartupWMClass=dev.tuist.guild
EOF
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$applications"
fi
xdg-mime default dev.tuist.guild.desktop x-scheme-handler/tuist
xdg-mime default dev.tuist.guild.desktop x-scheme-handler/luft
printf 'Installed Tuist in %s and registered tuist: and luft: links.\n' "$install_dir"
