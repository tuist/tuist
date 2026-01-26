#!/usr/bin/env bash
#MISE description="Check if translations are up to date"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOCKFILE="$ROOT/l10n.lock"

LANGUAGES=(ar es ja ko pl pt ru tr yue_Hant zh_Hans zh_Hant)

# Source files that need translation
GETTEXT_SOURCES=(
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
)

DOCS_SOURCES=(
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

get_translation_path() {
    local source="$1"
    local lang="$2"

    if [[ "$source" == *.pot ]]; then
        local domain
        domain=$(basename "$source" .pot)
        echo "server/priv/gettext/${lang}/LC_MESSAGES/${domain}.po"
    elif [[ "$source" == *en.json ]]; then
        echo "${source/en.json/${lang}.json}"
    fi
}

stale_sources=()
missing_translations=()
exit_code=0

# Check gettext sources
for source in "${GETTEXT_SOURCES[@]}"; do
    if [[ ! -f "$ROOT/$source" ]]; then
        continue
    fi

    current_hash=$(hash_file "$source")
    locked_hash=$(get_locked_hash "$source")

    if [[ "$current_hash" != "$locked_hash" ]]; then
        stale_sources+=("$source")
    fi

    # Check for missing translation files
    for lang in "${LANGUAGES[@]}"; do
        translation_path=$(get_translation_path "$source" "$lang")
        if [[ ! -f "$ROOT/$translation_path" ]]; then
            missing_translations+=("$translation_path")
        fi
    done
done

# Check docs sources
for source in "${DOCS_SOURCES[@]}"; do
    if [[ ! -f "$ROOT/$source" ]]; then
        continue
    fi

    current_hash=$(hash_file "$source")
    locked_hash=$(get_locked_hash "$source")

    if [[ "$current_hash" != "$locked_hash" ]]; then
        stale_sources+=("$source")
    fi

    # Check for missing translation files
    for lang in "${LANGUAGES[@]}"; do
        translation_path=$(get_translation_path "$source" "$lang")
        if [[ ! -f "$ROOT/$translation_path" ]]; then
            missing_translations+=("$translation_path")
        fi
    done
done

if [[ ${#stale_sources[@]} -eq 0 && ${#missing_translations[@]} -eq 0 ]]; then
    echo "All translations are up to date"
    exit 0
fi

if [[ ${#stale_sources[@]} -gt 0 ]]; then
    echo "Sources requiring translation:"
    for file in "${stale_sources[@]}"; do
        echo "  - $file"
    done
    exit_code=1
fi

if [[ ${#missing_translations[@]} -gt 0 ]]; then
    echo ""
    echo "Missing translation files:"
    for file in "${missing_translations[@]}"; do
        echo "  - $file"
    done
    exit_code=1
fi

exit $exit_code
