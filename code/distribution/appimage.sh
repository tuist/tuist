#!/usr/bin/env bash
# Explicit per-user integration; uninstall never removes account data.
set -euo pipefail

appimage_error() { printf '%s\n' "$*" >&2; return 1; }

appimage_quoted_exec() {
    local text=$1 char
    # Desktop Entry Exec escaping, NOT shell escaping. Percent is a field code.
    text=${text//%/%%}
    text=${text//\\/\\\\\\\\}
    for char in '"' '`' '$'; do text=${text//"$char"/\\\\$char}; done
    printf '"%s" %%u' "$text"
}

# readlink -f is unavailable on macOS. Resolve final links and parent directories.
appimage_realpath() (
    local path=$1 target count=0
    while :; do
        cd -P -- "$(dirname -- "$path")"
        path=$PWD/$(basename -- "$path")
        [[ -L $path ]] || break
        count=$((count + 1))
        [[ $count -le 40 ]] || { appimage_error 'Symlink loop'; exit 1; }
        target=$(readlink -- "$path")
        path=$target
    done
    [[ -e $path ]] || { appimage_error "Missing file: $path"; exit 1; }
    printf '%s\n' "$path"
)

appimage_remove_association() {
    local path=$1 launcher=$2 temp line ending remaining value result
    [[ -f $path ]] || return 0
    temp=$(mktemp)
    # Preserve unrelated lines byte-for-byte, including a missing final newline.
    while :; do
        line=''
        if IFS= read -r line; then ending=$'\n';
        else ending=''; [[ -n $line ]] || break; fi
        if [[ $line == x-scheme-handler/tuist=* ]]; then
            remaining=${line#*=}
            remaining=$(printf '%s' "$remaining" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            result=''
            while [[ -n $remaining ]]; do
                value=${remaining%%;*}
                if [[ -n $value && $value != "$launcher" ]]; then result=$result$value';'; fi
                if [[ $remaining == *';'* ]]; then remaining=${remaining#*;}; else break; fi
            done
            if [[ -n $result ]]; then printf 'x-scheme-handler/tuist=%s\n' "$result"; fi
        else
            printf '%s%s' "$line" "$ending"
        fi
        [[ -n $ending ]] || break
    done < "$path" > "$temp"
    # Write through the existing file, preserving its permissions/symlink behavior.
    if ! cmp -s -- "$temp" "$path"; then cat "$temp" > "$path"; fi
    rm -f -- "$temp"
}

appimage_extract() { (cd -- "$2" && "$1" --appimage-extract > /dev/null); }

appimage_integrate() (
    set -euo pipefail
    local image=$1 data=$2 install applications desktop expected config name temp root source_icon destination header
    install=$data/tuist-code-appimage
    applications=$data/applications
    desktop=$applications/dev.tuist.code.desktop
    if [[ -z $image ]]; then
        expected="Exec=$(appimage_quoted_exec "$install/TuistCode.AppImage")"
        if [[ -f $desktop ]] && grep -Fqx -- "$expected" "$desktop"; then
            rm -- "$desktop"
            config=${XDG_CONFIG_HOME-$HOME/.config}
            appimage_remove_association "$config/mimeapps.list" dev.tuist.code.desktop
            appimage_remove_association "$applications/mimeapps.list" dev.tuist.code.desktop
        fi
        # Fail on unexpected files rather than recursively deleting a directory.
        for name in TuistCode.AppImage icon.png; do rm -f -- "$install/$name"; done
        if [[ -e $install ]]; then rmdir -- "$install"; fi
    else
        image=$(appimage_realpath "$image")
        header=$(od -An -tx1 -N11 "$image" | tr -d ' \n')
        [[ ${header:0:8} == 7f454c46 && ${header:16:6} == 414902 ]] ||
            { appimage_error 'Expected a type-2 AppImage, not a portable executable'; exit 1; }
        # This executes a trusted AppImage: verify its release signature first.
        temp=$(mktemp -d)
        trap 'rm -rf -- "$temp"' EXIT
        appimage_extract "$image" "$temp"
        root=$(appimage_realpath "$temp/squashfs-root")
        source_icon=$(appimage_realpath "$root/.DirIcon")
        [[ -f $source_icon && $source_icon == "$root/"* ]] ||
            { appimage_error 'Missing embedded application icon'; exit 1; }
        mkdir -p -- "$install" "$applications"
        cp -p -- "$source_icon" "$install/icon.png"
        destination=$install/TuistCode.AppImage
        if [[ ! -e $destination ]] || [[ $image != "$(appimage_realpath "$destination")" ]]; then
            cp -p -- "$image" "$destination"
        fi
        chmod 755 "$destination"
        {
            printf '[Desktop Entry]\nType=Application\nName=Tuist Code\nComment=Tuist Code\nTerminal=false\nCategories=Development;\nMimeType=x-scheme-handler/tuist;\nStartupWMClass=dev.tuist.code\n'
            printf 'Icon=%s/icon.png\nExec=%s\n' "$install" "$(appimage_quoted_exec "$destination")"
        } > "$desktop"
        xdg-mime default dev.tuist.code.desktop x-scheme-handler/tuist
    fi
    if command -v update-desktop-database >/dev/null 2>&1 && [[ -d $applications ]]; then
        update-desktop-database "$applications"
    fi
)

appimage_main() {
    local image='' mode='' data
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install=*)
                [[ -z $mode && -n ${1#*=} ]] || { appimage_error 'Choose exactly one of --install PATH or --uninstall'; return 1; }
                mode=install; image=${1#*=}; shift;;
            --install)
                [[ -z $mode && $# -ge 2 && -n $2 ]] || { appimage_error 'Choose exactly one of --install PATH or --uninstall'; return 1; }
                mode=install; image=$2; shift 2;;
            --uninstall)
                [[ -z $mode ]] || { appimage_error 'Choose exactly one of --install PATH or --uninstall'; return 1; }
                mode=uninstall; shift;;
            -h|--help) printf 'Usage: appimage.sh (--install PATH | --uninstall)\nIntegrate an already trusted AppImage for the current user.\n'; return 0;;
            *) appimage_error "Unknown argument: $1"; return 1;;
        esac
    done
    [[ -n $mode ]] || { appimage_error 'Choose --install PATH or --uninstall'; return 1; }
    data=${XDG_DATA_HOME-$HOME/.local/share}
    [[ $data == /* ]] || { appimage_error 'XDG_DATA_HOME must be absolute'; return 1; }
    appimage_integrate "$image" "$data"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then appimage_main "$@"; fi
