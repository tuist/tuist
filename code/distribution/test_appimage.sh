#!/usr/bin/env bash
# Local files only: extraction and desktop registration are faked.
set -euo pipefail
# Git Bash cannot model Unix executable permissions or icon symlinks reliably.
# Windows integration is covered by the native NSIS install/uninstall smoke.
case $(uname -s) in
    MINGW*|MSYS*) printf 'SKIP: AppImage integration requires a Unix filesystem\n'; exit 0;;
esac
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=code/distribution/appimage.sh
source "$here/appimage.sh"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
export TEST_ROOT=$temp
export XDG_CONFIG_HOME=$temp/config XDG_DATA_HOME="$temp/data with spaces"
mkdir -p "$XDG_CONFIG_HOME"
printf keep > "$XDG_CONFIG_HOME/credentials.json"
[[ $(appimage_quoted_exec '/a folder/100%/TuistCode.AppImage') == '"/a folder/100%%/TuistCode.AppImage" %u' ]]
# shellcheck disable=SC2016
[[ $(appimage_quoted_exec '/a$folder/TuistCode.AppImage') == '"/a\\$folder/TuistCode.AppImage" %u' ]]
[[ $(appimage_quoted_exec '/a"`\folder/TuistCode.AppImage') == '"/a\\"\\`\\\\folder/TuistCode.AppImage" %u' ]]
printf 'PASS: Desktop Entry quoting for spaces, percent, dollar, quote, backtick, backslash\n'

# Exported functions override only the external operations, never file ownership checks.
appimage_extract() {
    printf 'extract\n' >> "$TEST_ROOT/events"
    mkdir "$2/squashfs-root"
    case ${TEST_ICON:-normal} in
        normal) printf 'brand icon' > "$2/squashfs-root/.DirIcon";;
        internal) printf 'brand icon' > "$2/squashfs-root/icon.png"; ln -s icon.png "$2/squashfs-root/.DirIcon";;
        escape) ln -s "$TEST_ROOT/outside-icon" "$2/squashfs-root/.DirIcon";;
        missing) :;;
    esac
}
xdg-mime() { printf 'mime %s\n' "$*" >> "$TEST_ROOT/events"; }
update-desktop-database() { printf 'database %s\n' "$*" >> "$TEST_ROOT/events"; }
export -f appimage_extract xdg-mime update-desktop-database
# Source again in a child, then replace just extraction (the file defines it).
run_integration() {
    bash -c 'source "$1"; eval "$2"; appimage_integrate "$3" "$4"' _ "$here/appimage.sh" "$(declare -f appimage_extract)" "$1" "$XDG_DATA_HOME"
}
image=$temp/TuistCode.AppImage
printf '\177ELF\000\000\000\000AI\002\000' > "$image"
run_integration "$image"
installed=$XDG_DATA_HOME/tuist-code-appimage/TuistCode.AppImage
desktop=$XDG_DATA_HOME/applications/dev.tuist.code.desktop
cmp -s "$image" "$installed"
[[ -x $installed && $(cat "${installed%/*}/icon.png") == 'brand icon' ]]
grep -Fqx -- "Exec=$(appimage_quoted_exec "$installed")" "$desktop"
grep -Fqx -- 'mime default dev.tuist.code.desktop x-scheme-handler/tuist' "$temp/events"
printf 'PASS: fake extraction installs bytes, icon, launcher and registers protocol\n'
printf '[Default Applications]\nx-scheme-handler/tuist=dev.tuist.code.desktop;other.desktop;\nx-scheme-handler/https=browser.desktop;\n' > "$XDG_CONFIG_HOME/mimeapps.list"
cp "$XDG_CONFIG_HOME/mimeapps.list" "$XDG_DATA_HOME/applications/mimeapps.list"
bash "$here/appimage.sh" --uninstall
[[ ! -e $installed && ! -e $desktop && $(cat "$XDG_CONFIG_HOME/credentials.json") == keep ]]
grep -Fqx 'x-scheme-handler/tuist=other.desktop;' "$XDG_CONFIG_HOME/mimeapps.list"
grep -Fqx 'x-scheme-handler/https=browser.desktop;' "$XDG_CONFIG_HOME/mimeapps.list"
if grep -Fq dev.tuist.code.desktop "$XDG_DATA_HOME/applications/mimeapps.list"; then
    printf 'FAIL: owned association remains\n'; exit 1
fi
printf 'PASS: uninstall retains credentials and unrelated protocol handlers\n'
printf '[Default Applications]\nx-scheme-handler/https=browser.desktop;' > "$temp/no-final-newline"
cp "$temp/no-final-newline" "$temp/no-final-newline.expected"
appimage_remove_association "$temp/no-final-newline" dev.tuist.code.desktop
cmp -s "$temp/no-final-newline" "$temp/no-final-newline.expected"
export TEST_ICON=internal
run_integration "$image"
printf '[Desktop Entry]\nExec=/some/other/portable/Tuist %%u\n' > "$desktop"
cp "$desktop" "$temp/replaced.desktop"
printf '[Default Applications]\nx-scheme-handler/tuist=dev.tuist.code.desktop;\n' > "$XDG_CONFIG_HOME/mimeapps.list"
cp "$XDG_CONFIG_HOME/mimeapps.list" "$temp/replaced.mimeapps"
bash "$here/appimage.sh" --uninstall
cmp -s "$desktop" "$temp/replaced.desktop"
cmp -s "$XDG_CONFIG_HOME/mimeapps.list" "$temp/replaced.mimeapps"
[[ ! -e $installed ]]
printf 'PASS: internal icon symlinks work; replaced launcher and associations survive uninstall\n'
printf icon > "$temp/outside-icon"
for TEST_ICON in escape missing; do
    export TEST_ICON
    if run_integration "$image" > "$temp/output" 2>&1; then printf 'FAIL: accepted %s icon\n' "$TEST_ICON"; exit 1; fi
done
printf '\177ELF\000\000\000\000\000\000\000' > "$temp/portable"
if run_integration "$temp/portable" > "$temp/output" 2>&1; then printf 'FAIL: accepted portable executable\n'; exit 1; fi
if XDG_DATA_HOME=relative bash "$here/appimage.sh" --uninstall > "$temp/output" 2>&1; then printf 'FAIL: accepted relative data home\n'; exit 1; fi
if bash "$here/appimage.sh" --install "$image" --uninstall > "$temp/output" 2>&1; then printf 'FAIL: accepted conflicting modes\n'; exit 1; fi
printf 'PASS: missing/escaping icons, portable executable, relative data home and conflicting modes rejected\n'
