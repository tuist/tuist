#!/usr/bin/env bash
#MISE description="Update the l10n lockfile with current source hashes"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOCKFILE="$ROOT/l10n.lock"

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

{
    echo "# L10N Lockfile - Tracks source file hashes for translation"
    echo "# Format: <source-file> <sha256-hash>"
    echo "# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""

    for source in "${SOURCES[@]}"; do
        if [[ -f "$ROOT/$source" ]]; then
            hash=$(hash_file "$source")
            echo "$source $hash"
        fi
    done
} > "$LOCKFILE"

echo "Lockfile updated: $LOCKFILE"
