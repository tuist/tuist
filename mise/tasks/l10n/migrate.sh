#!/usr/bin/env bash
#MISE description="Migrate from Weblate: clean up inconsistencies and initialize lockfile"
#USAGE flag "-n --dry-run" help="Show what would be done without making changes"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOCKFILE="$ROOT/l10n.lock"

LANGUAGES=(ar es ja ko pl pt ru tr yue_Hant zh_Hans zh_Hant)

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

DRY_RUN="${usage_dry_run:-false}"

log() {
    echo "$@"
}

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

echo "=== L10N Migration from Weblate ==="
echo ""

# Step 1: Check for missing PO files and create stubs
echo "Step 1: Checking for missing translation files..."
missing_count=0

for source in "${GETTEXT_SOURCES[@]}"; do
    if [[ ! -f "$ROOT/$source" ]]; then
        continue
    fi

    domain=$(basename "$source" .pot)

    for lang in "${LANGUAGES[@]}"; do
        po_path="server/priv/gettext/${lang}/LC_MESSAGES/${domain}.po"
        full_path="$ROOT/$po_path"

        if [[ ! -f "$full_path" ]]; then
            log "  Missing: $po_path"
            ((missing_count++))

            if [[ "$DRY_RUN" != "true" ]]; then
                mkdir -p "$(dirname "$full_path")"

                # Create a stub PO file from the POT template
                {
                    echo "# Translation for $lang"
                    echo "# This file needs translation"
                    echo 'msgid ""'
                    echo "msgstr \"\""
                    echo "\"Content-Type: text/plain; charset=UTF-8\\n\""
                    echo "\"Language: ${lang}\\n\""
                    echo ""

                    # Copy msgid entries from POT with empty msgstr
                    grep -A1 '^msgid "' "$ROOT/$source" | while IFS= read -r line; do
                        if [[ "$line" == msgid* ]]; then
                            echo "$line"
                        elif [[ "$line" == msgstr* ]]; then
                            echo 'msgstr ""'
                            echo ""
                        fi
                    done
                } > "$full_path"

                log "  Created stub: $po_path"
            fi
        fi
    done
done

if [[ $missing_count -eq 0 ]]; then
    log "  No missing translation files."
else
    log "  Found $missing_count missing files."
fi

echo ""

# Step 2: Clean up docs JSON files (remove stale keys, add missing keys)
echo "Step 2: Syncing docs translation JSON structure..."

en_json="$ROOT/docs/.vitepress/strings/en.json"

if [[ -f "$en_json" ]]; then
    # Get the structure from English file
    en_keys=$(jq -r 'paths(scalars) | join(".")' "$en_json" | sort)

    for lang in "${LANGUAGES[@]}"; do
        lang_json="$ROOT/docs/.vitepress/strings/${lang}.json"

        if [[ ! -f "$lang_json" ]]; then
            log "  Missing: docs/.vitepress/strings/${lang}.json"
            if [[ "$DRY_RUN" != "true" ]]; then
                # Copy English as template
                cp "$en_json" "$lang_json"
                log "  Created from English template: ${lang}.json"
            fi
            continue
        fi

        lang_keys=$(jq -r 'paths(scalars) | join(".")' "$lang_json" | sort)

        # Find missing keys
        missing_keys=$(comm -23 <(echo "$en_keys") <(echo "$lang_keys"))
        # Find extra keys
        extra_keys=$(comm -13 <(echo "$en_keys") <(echo "$lang_keys"))

        if [[ -n "$missing_keys" ]] || [[ -n "$extra_keys" ]]; then
            log "  $lang.json:"

            if [[ -n "$missing_keys" ]]; then
                missing_count=$(echo "$missing_keys" | wc -l | tr -d ' ')
                log "    - $missing_count missing keys"
            fi

            if [[ -n "$extra_keys" ]]; then
                extra_count=$(echo "$extra_keys" | wc -l | tr -d ' ')
                log "    - $extra_count extra/stale keys"
            fi

            if [[ "$DRY_RUN" != "true" ]]; then
                # Sync structure: use jq to merge, keeping existing translations
                # but removing extra keys and adding missing ones from English
                temp_file=$(mktemp)

                # This preserves existing translations while syncing structure
                jq -s '
                    def deep_merge(a; b):
                        a as $a | b as $b |
                        if ($a | type) == "object" and ($b | type) == "object" then
                            ($a | keys) + ($b | keys) | unique | map(
                                . as $k |
                                if ($a | has($k)) and ($b | has($k)) then
                                    {($k): deep_merge($a[$k]; $b[$k])}
                                elif ($b | has($k)) then
                                    {($k): $b[$k]}
                                else
                                    {($k): $a[$k]}
                                end
                            ) | add
                        elif $b != null then $b
                        else $a
                        end;

                    # Start with English structure, overlay with existing translations
                    # Then filter to only keep keys that exist in English
                    .[0] as $en | .[1] as $lang |
                    deep_merge($en; $lang) |
                    # Filter to match English structure (removes extra keys)
                    walk(if type == "object" then with_entries(select(.key as $k | $en | .. | objects | has($k) // false)) else . end)
                ' "$en_json" "$lang_json" > "$temp_file"

                # Simpler approach: just ensure the file is valid JSON
                if jq . "$temp_file" > /dev/null 2>&1; then
                    mv "$temp_file" "$lang_json"
                    log "    Synced structure"
                else
                    rm -f "$temp_file"
                    log "    Warning: Could not sync, keeping original"
                fi
            fi
        fi
    done
else
    log "  Warning: English source file not found at $en_json"
fi

echo ""

# Step 3: Remove fuzzy markers from PO files (they have actual translations)
echo "Step 3: Checking for fuzzy markers in PO files..."
fuzzy_count=0

for lang in "${LANGUAGES[@]}"; do
    po_dir="$ROOT/server/priv/gettext/${lang}/LC_MESSAGES"

    if [[ -d "$po_dir" ]]; then
        for po_file in "$po_dir"/*.po; do
            if [[ -f "$po_file" ]]; then
                count=$(grep -c "^#, fuzzy" "$po_file" 2>/dev/null | head -1 || echo "0")
                count="${count:-0}"
                if [[ "$count" =~ ^[0-9]+$ ]] && [[ "$count" -gt 0 ]]; then
                    log "  $(basename "$po_file") ($lang): $count fuzzy markers"
                    ((fuzzy_count += count))

                    if [[ "$DRY_RUN" != "true" ]]; then
                        # Remove fuzzy markers
                        sed -i '' '/^#, fuzzy$/d' "$po_file" 2>/dev/null || \
                        sed -i '/^#, fuzzy$/d' "$po_file"
                    fi
                fi
            fi
        done
    fi
done

if [[ $fuzzy_count -eq 0 ]]; then
    log "  No fuzzy markers found."
else
    log "  Removed $fuzzy_count fuzzy markers."
fi

echo ""

# Step 4: Initialize lockfile
echo "Step 4: Initializing lockfile..."

if [[ "$DRY_RUN" != "true" ]]; then
    mise run l10n:update-lockfile
else
    log "[DRY RUN] Would run: mise run l10n:update-lockfile"
fi

echo ""

# Step 5: Summary
echo "=== Migration Summary ==="
echo ""
echo "The following files have been modified/created:"
echo "  - l10n.lock (new lockfile)"
echo "  - L10N.md (translation context - create manually if needed)"
echo ""
echo "Next steps:"
echo "  1. Review the changes: git diff"
echo "  2. Remove Weblate configuration if present"
echo "  3. Update CI workflow to use 'mise run l10n:status'"
echo "  4. Commit the changes"
echo ""
echo "For languages with many empty translations (pt, yue_Hant),"
echo "run 'mise run l10n:sync --language <lang>' to fill them in."
