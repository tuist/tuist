#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
test $# = 1 || { echo 'Usage: smoke.sh STAGING_DIRECTORY' >&2; exit 1; }
stage=$(cd "$1" && pwd)
shopt -s nullglob
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

case $(uname -s) in
    Linux)
        images=("$stage/packages/"*.AppImage)
        test "${#images[@]}" = 1
        (cd "$temp"; "${images[0]}" --appimage-extract >/dev/null)
        root=$temp/squashfs-root
        entries=("$root/"*.desktop)
        test "${#entries[@]}" -gt 0
        grep -q 'x-scheme-handler/tuist' "${entries[0]}"
        if grep -q 'x-scheme-handler/https' "${entries[0]}"; then echo 'Installer claimed HTTPS' >&2; exit 1; fi
        grep -q 'Icon=' "${entries[0]}"
        grep -q 'Exec=' "${entries[0]}"
        test -n "$(find "$root" -name '*.png' -print -quit)"
        test -e "$root/AppRun"
        export HOME=$temp/home XDG_DATA_HOME=$temp/data XDG_CONFIG_HOME=$temp/config
        mkdir -p "$HOME" "$XDG_CONFIG_HOME"
        printf 'must survive uninstall' > "$XDG_CONFIG_HOME/credentials.json"
        bash "$HERE/appimage.sh" --install "${images[0]}"
        test -f "$XDG_DATA_HOME/tuist-desktop-appimage/Tuist.AppImage"
        test -f "$XDG_DATA_HOME/applications/dev.tuist.desktop.desktop"
        bash "$HERE/appimage.sh" --uninstall
        test ! -e "$XDG_DATA_HOME/tuist-desktop-appimage"
        test ! -e "$XDG_DATA_HOME/applications/dev.tuist.desktop.desktop"
        test "$(cat "$XDG_CONFIG_HOME/credentials.json")" = 'must survive uninstall'
        ;;
    MINGW*|MSYS*)
        test "${CI:-}" = true || { echo 'NSIS smoke is restricted to disposable CI hosts' >&2; exit 1; }
        export MSYS_NO_PATHCONV=1
        installers=("$stage/packages/"*.exe)
        test "${#installers[@]}" = 1
        destination=$(cygpath -u "$LOCALAPPDATA")/Tuist
        programs=$(cygpath -u "$APPDATA")/Microsoft/Windows/Start\ Menu/Programs
        test ! -e "$destination" || { echo 'Refuse to replace an existing installation' >&2; exit 1; }
        "${installers[0]}" /S
        test "$(tr -d '\r\n' < "$destination/tuist-installation")" = nsis
        test -f "$destination/Tuist.exe"
        test -f "$destination/uninstall.exe"
        command=$(reg.exe query 'HKCU\Software\Classes\tuist\shell\open\command' /ve)
        [[ $command == *Tuist.exe* && $command == *%1* ]]
        test -n "$(find "$programs" -name Tuist.lnk -print -quit)"
        mkdir -p "$destination/credentials"
        printf 'must survive uninstall' > "$destination/credentials/distribution-smoke.json"
        "$destination/uninstall.exe" /S
        for ((i=0; i<60; i++)); do
            if test ! -e "$destination/Tuist.exe" && ! reg.exe query 'HKCU\Software\Classes\tuist' >/dev/null 2>&1; then break; fi
            sleep 1
        done
        test ! -e "$destination/Tuist.exe"
        test ! -e "$destination/tuist-installation"
        test -z "$(find "$programs" -name Tuist.lnk -print -quit)"
        if reg.exe query 'HKCU\Software\Classes\tuist' >/dev/null 2>&1; then echo 'Uninstall left protocol registered' >&2; exit 1; fi
        test "$(cat "$destination/credentials/distribution-smoke.json")" = 'must survive uninstall'
        rm "$destination/credentials/distribution-smoke.json"
        rmdir "$destination/credentials"
        ;;
    *) echo 'Run packaging smoke natively on Linux/Windows' >&2; exit 1;;
esac
