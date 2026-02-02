#!/usr/bin/env bash
#MISE description="Output JSON of files needing translation (for CI)"
#MISE hide=true
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOCKFILE="$ROOT/l10n.lock"

LANGUAGES=(ar es ja ko pl pt ru tr yue_Hant zh_Hans zh_Hant)

# Source files that need translation
SOURCES=(
    "server/priv/gettext/default.pot"
    "server/priv/gettext/errors.pot"
    "server/priv/gettext/marketing.pot"
    "server/priv/gettext/dashboard.pot"
    "server/priv/gettext/dashboard_account.pot"
    "server/priv/gettext/dashboard_auth.pot"
    "server/priv/gettext/dashboard_builds.pot"
    "server/priv/gettext/dashboard_cache.pot"
    "server/priv/gettext/dashboard_integrations.pot"
    "server/priv/gettext/dashboard_previews.pot"
    "server/priv/gettext/dashboard_projects.pot"
    "server/priv/gettext/dashboard_qa.pot"
    "server/priv/gettext/dashboard_slack.pot"
    "server/priv/gettext/dashboard_tests.pot"
    "docs/.vitepress/strings/en.json"
)

hash_file() {
    local file="$1"
    if [[ -f "$ROOT/$file" ]]; then
        shasum -a 256 "$ROOT/$file" | cut -d' ' -f1
    else
        echo "MISSING"
    fi
}

get_locked_hash() {
    local file="$1"
    if [[ -f "$LOCKFILE" ]]; then
        grep "^${file} " "$LOCKFILE" 2>/dev/null | cut -d' ' -f2 || echo ""
    else
        echo ""
    fi
}

stale=()

for source in "${SOURCES[@]}"; do
    if [[ ! -f "$ROOT/$source" ]]; then
        continue
    fi

    current_hash=$(hash_file "$source")
    locked_hash=$(get_locked_hash "$source")

    if [[ "$current_hash" != "$locked_hash" ]]; then
        stale+=("\"$source\"")
    fi
done

# Build JSON output
stale_json=$(IFS=,; echo "[${stale[*]:-}]")

langs_json=$(printf '"%s",' "${LANGUAGES[@]}")
langs_json="[${langs_json%,}]"

echo "{\"stale\":$stale_json,\"languages\":$langs_json}"
