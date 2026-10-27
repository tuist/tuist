#!/usr/bin/env bash
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }
[[ $# = 0 || $# = 2 ]] || fail "Pass the source .appex and its destination inside the host app"
source_bundle=${1:-${ATLAS_WIDGET_SOURCE:-}}
destination=${2:-${ATLAS_WIDGET_DESTINATION:-}}
[[ -n "$source_bundle" && -n "$destination" ]] || fail "Set ATLAS_WIDGET_SOURCE and ATLAS_WIDGET_DESTINATION"
product=$(basename "$source_bundle" .appex)
[[ "$product" = AtlasLiveActivity || "$product" = AtlasShare ]] || fail "Unexpected extension"
[[ "$source_bundle" = */"$product.appex" && -d "$source_bundle" && ! -L "$source_bundle" ]] || fail "Expected a built Atlas extension"
[[ -f "$source_bundle/Info.plist" && -x "$source_bundle/$product" ]] || fail "The extension bundle is incomplete"
app=${destination%/PlugIns/"$product.appex"}
[[ "$app" != "$destination" && "$app" = *.app && -f "$app/Info.plist" ]] || fail "The destination must be inside an assembled host .app/PlugIns"
[[ ! -L "$app/PlugIns" && ! -L "$destination" ]] || fail "Refusing a symlinked extension destination"
source_bundle="$(cd "$(dirname "$source_bundle")" && pwd -P)/$product.appex"
app=$(cd "$app" && pwd -P)
destination="$app/PlugIns/$product.appex"
[[ "$source_bundle" != "$destination" ]] || fail "The source and destination must differ"

mkdir -p "$app/PlugIns"
temporary=$(mktemp -d "$app/PlugIns/.AtlasLiveActivity.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ditto "$source_bundle" "$temporary/$product.appex"
# Replacing this one tree removes obsolete resources without touching siblings.
rm -rf "$destination"
mv "$temporary/$product.appex" "$destination"
