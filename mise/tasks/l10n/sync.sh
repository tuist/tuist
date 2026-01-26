#!/usr/bin/env bash
#MISE description="Sync translations for changed source files using Vertex AI Gemini"
#USAGE flag "-f --force" help="Force retranslation of all files"
#USAGE flag "-l --language <lang>" help="Only translate to specific language"
#USAGE flag "-s --source <file>" help="Only translate specific source file"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOCKFILE="$ROOT/l10n.lock"
CONTEXT_FILE="$ROOT/L10N.md"

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

# Language name mapping for translation prompts
declare -A LANG_NAMES=(
    ["ar"]="Arabic"
    ["es"]="Spanish"
    ["ja"]="Japanese"
    ["ko"]="Korean"
    ["pl"]="Polish"
    ["pt"]="Portuguese (Brazilian)"
    ["ru"]="Russian"
    ["tr"]="Turkish"
    ["yue_Hant"]="Cantonese (Traditional Chinese)"
    ["zh_Hans"]="Chinese (Simplified)"
    ["zh_Hant"]="Chinese (Traditional)"
)

# Vertex AI configuration
VERTEX_PROJECT="${VERTEX_AI_PROJECT:-}"
VERTEX_LOCATION="${VERTEX_AI_LOCATION:-us-central1}"
VERTEX_MODEL="${VERTEX_AI_MODEL:-gemini-2.5-flash-lite}"

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

translate_with_vertex() {
    local prompt="$1"

    if [[ -z "$VERTEX_PROJECT" ]]; then
        echo "Error: VERTEX_AI_PROJECT environment variable not set" >&2
        exit 1
    fi

    # Get access token using gcloud
    local token
    token=$(gcloud auth print-access-token 2>/dev/null) || {
        echo "Error: Failed to get access token. Run 'gcloud auth login' first." >&2
        exit 1
    }

    local endpoint="https://${VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}/locations/${VERTEX_LOCATION}/publishers/google/models/${VERTEX_MODEL}:generateContent"

    # Call Vertex AI Gemini API
    local response
    response=$(curl -s -X POST "$endpoint" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg prompt "$prompt" '{
            contents: [{
                role: "user",
                parts: [{text: $prompt}]
            }],
            generationConfig: {
                temperature: 0.1,
                maxOutputTokens: 8192
            }
        }')")

    # Check for errors
    local error
    error=$(echo "$response" | jq -r '.error.message // empty')
    if [[ -n "$error" ]]; then
        echo "Error from Vertex AI: $error" >&2
        return 1
    fi

    # Extract the text from the response
    echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty'
}

translate_pot_file() {
    local source="$1"
    local lang="$2"
    local output="$3"
    local context="$4"

    local lang_name="${LANG_NAMES[$lang]}"

    echo "    Translating $source to $lang_name..."

    mkdir -p "$(dirname "$ROOT/$output")"

    # Read the POT file content
    local pot_content
    pot_content=$(cat "$ROOT/$source")

    local prompt="You are a professional translator for Tuist, a developer tools company for iOS/macOS.

CONTEXT:
$context

TASK:
Translate the following gettext PO template to $lang_name.

RULES:
- Return ONLY the translated PO file content, nothing else
- Preserve all msgid strings exactly as they are
- Translate only the msgstr values
- Keep placeholders like %{variable} exactly as they appear
- Do not translate product names (Tuist, Xcode, Swift, Apple, Air)
- Do not translate technical terms in code context
- Preserve all formatting, line breaks, and special characters
- The header msgstr should contain appropriate metadata for $lang_name

SOURCE PO TEMPLATE:
$pot_content"

    local translated
    translated=$(translate_with_vertex "$prompt")

    if [[ -n "$translated" ]]; then
        echo "$translated" > "$ROOT/$output"
        echo "    Wrote: $output"
    else
        echo "    Error: Failed to translate $source to $lang" >&2
    fi
}

translate_json_file() {
    local source="$1"
    local lang="$2"
    local output="$3"
    local context="$4"

    local lang_name="${LANG_NAMES[$lang]}"

    echo "    Translating $source to $lang_name..."

    # Read the source JSON
    local json_content
    json_content=$(cat "$ROOT/$source")

    local prompt="You are a professional translator for Tuist, a developer tools company for iOS/macOS.

CONTEXT:
$context

TASK:
Translate the following JSON file to $lang_name.

RULES:
- Return ONLY valid JSON, nothing else (no markdown code blocks)
- Preserve all JSON keys exactly as they are
- Translate only string values
- Keep placeholders like {{variable}} exactly as they appear
- Do not translate product names (Tuist, Xcode, Swift, Apple)
- Preserve the exact JSON structure

SOURCE JSON:
$json_content"

    local translated
    translated=$(translate_with_vertex "$prompt")

    if [[ -n "$translated" ]]; then
        # Strip markdown code blocks if present
        translated=$(echo "$translated" | sed -n '/^```/,/^```/{ /^```/d; p; }' || echo "$translated")
        # If no code blocks, use original
        if [[ -z "$translated" ]]; then
            translated=$(translate_with_vertex "$prompt")
        fi

        # Validate JSON and write
        if echo "$translated" | jq . > /dev/null 2>&1; then
            echo "$translated" | jq . > "$ROOT/$output"
            echo "    Wrote: $output"
        else
            echo "    Error: Invalid JSON returned for $output" >&2
            echo "    Response was: $translated" >&2
        fi
    else
        echo "    Error: Failed to translate $source to $lang" >&2
    fi
}

# Determine which languages to process
if [[ -n "${usage_language:-}" ]]; then
    LANGUAGES=("$usage_language")
fi

# Read context file
context=""
if [[ -f "$CONTEXT_FILE" ]]; then
    context=$(cat "$CONTEXT_FILE")
fi

# Collect sources to translate
sources_to_translate=()

if [[ -n "${usage_source:-}" ]]; then
    sources_to_translate=("$usage_source")
elif [[ "${usage_force:-}" == "true" ]]; then
    sources_to_translate=("${GETTEXT_SOURCES[@]}" "${DOCS_SOURCES[@]}")
else
    # Only translate changed sources
    for source in "${GETTEXT_SOURCES[@]}" "${DOCS_SOURCES[@]}"; do
        if [[ ! -f "$ROOT/$source" ]]; then
            continue
        fi

        current_hash=$(hash_file "$source")
        locked_hash=$(get_locked_hash "$source")

        if [[ "$current_hash" != "$locked_hash" ]]; then
            sources_to_translate+=("$source")
        fi
    done
fi

if [[ ${#sources_to_translate[@]} -eq 0 ]]; then
    echo "No files need translation"
    exit 0
fi

echo "Using Vertex AI Gemini ($VERTEX_MODEL) in project: $VERTEX_PROJECT"
echo "Translating ${#sources_to_translate[@]} source file(s) to ${#LANGUAGES[@]} language(s)..."
echo ""

for source in "${sources_to_translate[@]}"; do
    echo "Source: $source"

    for lang in "${LANGUAGES[@]}"; do
        output=$(get_translation_path "$source" "$lang")

        if [[ "$source" == *.pot ]]; then
            translate_pot_file "$source" "$lang" "$output" "$context"
        elif [[ "$source" == *.json ]]; then
            translate_json_file "$source" "$lang" "$output" "$context"
        fi
    done

    echo ""
done

echo "Translation complete. Run 'mise run l10n:update-lockfile' to update the lockfile."
