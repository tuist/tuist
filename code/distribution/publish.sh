#!/usr/bin/env bash
# Trusted manual publisher. Never run from contributor code or a PR job.
set -euo pipefail

# shellcheck source=release.sh
source "$(dirname "${BASH_SOURCE[0]}")/release.sh"

publish_error() { printf '%s\n' "$*" >&2; return 1; }

publish_api() { gh api "repos/tuist/tuist/$1"; }

publish_main() (
    set -euo pipefail
    local assets='' feed='' sha='' key value tag channel tags releases published temp path name remote notes
    local files=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --assets=*|--feed=*|--sha=*)
                case $1 in --assets=*) assets=${1#*=};; --feed=*) feed=${1#*=};; --sha=*) sha=${1#*=};; esac
                shift;;
            --assets|--feed|--sha)
                [[ $# -ge 2 && -n $2 ]] || { publish_error "Missing value for $1"; exit 1; }
                case $1 in --assets) assets=$2;; --feed) feed=$2;; --sha) sha=$2;; esac
                shift 2;;
            -h|--help) printf 'Usage: publish.sh --assets DIR --feed DIR --sha SHA\nTrusted main only; publishes immutable payloads before updating the mutable feed.\n'; exit 0;;
            *) publish_error "Unknown argument: $1"; exit 1;;
        esac
    done
    [[ -n $assets && -n $feed && -n $sha ]] || { publish_error 'Require --assets, --feed and --sha'; exit 1; }
    [[ ${GITHUB_REPOSITORY:-} == tuist/tuist && ${GITHUB_REF:-} == refs/heads/main ]] ||
        { publish_error 'Publication is restricted to trusted main'; exit 1; }
    [[ $sha =~ ^[0-9a-f]{40}$ && ${GITHUB_SHA:-} == "$sha" ]] ||
        { publish_error 'Source must equal the workflow main SHA'; exit 1; }
    remote=$(git ls-remote origin refs/heads/main)
    [[ ${remote%%[[:space:]]*} == "$sha" ]] || { publish_error 'Main advanced; rebuild the current main instead'; exit 1; }
    key=$(printf '%s' "${DESKTOP_UPDATE_PUBLIC_KEY:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -n $key ]] || { publish_error 'Provision DESKTOP_UPDATE_PUBLIC_KEY before releasing'; exit 1; }
    verify "$feed/latest.json" "$key"
    value=$(version "$ROOT")
    jq -e --arg value "$value" '.version == $value' "$feed/latest.json" >/dev/null ||
        { publish_error 'Feed version differs from the trusted source workspace'; exit 1; }
    tag="desktop@$value"
    channel=$(publish_api releases/tags/desktop-updates)
    jq -e '.immutable == false and .draft == false and .prerelease == false' <<< "$channel" >/dev/null ||
        { publish_error 'Provision a published mutable desktop-updates release first'; exit 1; }
    tags=$(git ls-remote --tags origin "refs/tags/$tag")
    [[ -z $tags ]] || { publish_error 'Immutable version tag already exists; never replace or resume with new bytes'; exit 1; }
    releases=$(gh api --paginate --slurp 'repos/tuist/tuist/releases?per_page=100')
    jq -e --arg tag "$tag" 'type == "array" and all(.[]; type == "array") and all(.[][]; .tag_name != $tag)' <<< "$releases" >/dev/null ||
        { publish_error 'Version release already exists, including drafts'; exit 1; }
    [[ -d $assets ]] || { publish_error 'Missing assets directory'; exit 1; }
    # Globs preserve spaces/newlines and include dotfiles, as Path.iterdir did.
    shopt -s nullglob dotglob
    for path in "$assets"/*; do
        [[ -f $path ]] || continue
        files+=("$path")
        case $path in *.exe|*.AppImage|*.tar.gz) verify "$path" "$key";; esac
    done
    notes=$(jq -er '.notes // "" | strings' "$feed/latest.json")
    gh release create "$tag" --repo tuist/tuist --target "$sha" --draft --title "Tuist Code $value" --notes "$notes"
    gh release upload "$tag" --repo tuist/tuist "${files[@]}"
    gh release edit "$tag" --repo tuist/tuist --draft=false --latest=false
    published=$(publish_api "releases/tags/$tag")
    jq -e '.immutable == true and .draft == false' <<< "$published" >/dev/null ||
        { publish_error 'Enable GitHub immutable releases; feed was NOT changed'; exit 1; }
    for path in "${files[@]}"; do
        name=${path##*/}
        jq -e --arg name "$name" 'any(.assets[]; .name == $name)' <<< "$published" >/dev/null ||
            { publish_error 'Published immutable release lacks expected assets; feed was NOT changed'; exit 1; }
    done
    temp=$(mktemp -d)
    trap 'rm -rf -- "$temp"' EXIT
    gh release download "$tag" --repo tuist/tuist --dir "$temp"
    for path in "${files[@]}"; do
        cmp -s -- "$temp/${path##*/}" "$path" || { publish_error 'Published bytes differ; feed was NOT changed'; exit 1; }
    done
    # Not atomic: clients reject mismatched manifest/signature pairs and retry.
    gh release upload desktop-updates --repo tuist/tuist --clobber "$feed/latest.json" "$feed/latest.json.sig"
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then publish_main "$@"; fi
