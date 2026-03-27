#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly RCLONE_REMOTE="tigris"
readonly REGISTRY_BUCKET="tuist-registry"
readonly REGISTRY_ROOT="${RCLONE_REMOTE}:${REGISTRY_BUCKET}"
readonly DEPLOY_PRODUCTION_CONFIG_FILE="${PROJECT_ROOT}/cache/config/deploy.production.yml"
readonly LOCAL_REGISTRY_ROOT="/cas/registry/swift"

cleanup_paths=()

log() {
    printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

warn() {
    printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2
}

fail() {
    printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<EOF
Usage: ${SCRIPT_NAME} scope/name [version]

Examples:
  ${SCRIPT_NAME} onevcat/rainbow
  ${SCRIPT_NAME} onevcat/Rainbow 4.2.1
  ${SCRIPT_NAME} onevcat/Rainbow v2.0.0-alpha.1
EOF
    exit 1
}

cleanup() {
    local path

    for path in "${cleanup_paths[@]:-}"; do
        if [[ -n "$path" && -e "$path" ]]; then
            rm -rf "$path"
        fi
    done
}

trap cleanup EXIT

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        fail "Missing required command: ${command_name}"
    fi
}

print_rclone_setup_instructions() {
    cat >&2 <<EOF
[${SCRIPT_NAME}] ERROR: rclone remote "${RCLONE_REMOTE}" is not configured.

Set it up with the production registry Tigris credentials from 1Password/Kamal secrets, for example:
  export S3_ACCESS_KEY_ID='...'
  export S3_SECRET_ACCESS_KEY='...'
  export S3_HOST='fly.storage.tigris.dev'
  export S3_REGION='auto'

  rclone config create ${RCLONE_REMOTE} s3 \
    provider Other \
    env_auth false \
    access_key_id "\$S3_ACCESS_KEY_ID" \
    secret_access_key "\$S3_SECRET_ACCESS_KEY" \
    endpoint "https://\$S3_HOST" \
    region "\${S3_REGION:-auto}"

Then verify it:
  rclone lsf ${REGISTRY_ROOT}/registry/metadata/ | head
EOF
}

check_rclone_configuration() {
    local remotes

    log "Checking required commands"
    require_command rclone
    require_command jq
    require_command ssh

    log "Checking rclone remote configuration"
    remotes="$(rclone listremotes 2>/dev/null || true)"

    if ! grep -Fxq "${RCLONE_REMOTE}:" <<<"$remotes"; then
        print_rclone_setup_instructions
        exit 1
    fi

    log "Found rclone remote \"${RCLONE_REMOTE}\""
    log "Verifying read access to ${REGISTRY_ROOT}"

    if ! rclone lsf "${REGISTRY_ROOT}/registry/metadata/" >/dev/null 2>&1; then
        fail "Unable to read ${REGISTRY_ROOT}. Check the configured ${RCLONE_REMOTE} credentials."
    fi
}

read_all_production_hosts() {
    local hosts=()

    if [[ ! -f "$DEPLOY_PRODUCTION_CONFIG_FILE" ]]; then
        fail "Missing production deploy config file: ${DEPLOY_PRODUCTION_CONFIG_FILE}"
    fi

    mapfile -t hosts < <(sed -n '/^[[:space:]]*hosts:[[:space:]]*$/,$ {
        /^[[:space:]]*hosts:/d
        /^[[:space:]]*-[[:space:]]/ { s/^[[:space:]]*-[[:space:]]*//; p; b; }
        /^[[:space:]]*$/b
        q
    }' "$DEPLOY_PRODUCTION_CONFIG_FILE")

    if [[ "${#hosts[@]}" -eq 0 ]]; then
        fail "Unable to determine any production cache hosts from ${DEPLOY_PRODUCTION_CONFIG_FILE}"
    fi

    printf '%s\n' "${hosts[@]}"
}

purge_local_caches() {
    local local_path="$1"
    local hosts=()
    local host

    mapfile -t hosts < <(read_all_production_hosts)

    log "Purging local disk caches from ${#hosts[@]} production nodes"

    for host in "${hosts[@]}"; do
        log "Removing ${local_path} on ${host}"
        if ssh -o BatchMode=yes "$host" rm -rf "$local_path"; then
            log "Purged local cache on ${host}"
        else
            warn "Failed to purge local cache on ${host} (continuing with other nodes)"
        fi
    done
}

parse_package() {
    local package="$1"

    if [[ "$package" != */* ]]; then
        fail "Package must be in scope/name format"
    fi

    raw_scope="${package%%/*}"
    raw_name="${package#*/}"

    if [[ -z "$raw_scope" || -z "$raw_name" || "$raw_name" == */* ]]; then
        fail "Package must be in scope/name format"
    fi
}

normalize_scope() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_name() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '.' '_'
}

strip_leading_zeros() {
    local value="$1"

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s' "$((10#$value))"
    else
        printf '%s' "$value"
    fi
}

add_trailing_semantic_version_zeros() {
    local version="$1"
    local parts=()

    IFS='.' read -r -a parts <<<"$version"

    case "${#parts[@]}" in
        1)
            printf '%s.0.0' "$(strip_leading_zeros "${parts[0]}")"
            ;;
        2)
            printf '%s.%s.0' \
                "$(strip_leading_zeros "${parts[0]}")" \
                "$(strip_leading_zeros "${parts[1]}")"
            ;;
        3)
            printf '%s.%s.%s' \
                "$(strip_leading_zeros "${parts[0]}")" \
                "$(strip_leading_zeros "${parts[1]}")" \
                "$(strip_leading_zeros "${parts[2]}")"
            ;;
        *)
            printf '%s' "$version"
            ;;
    esac
}

normalize_version() {
    local version="${1#v}"
    local hyphen_count
    local base
    local prerelease
    local stripped

    stripped="${version//-/}"
    hyphen_count=$(( ${#version} - ${#stripped} ))

    if [[ "$hyphen_count" == "1" ]]; then
        base="${version%%-*}"
        prerelease="${version#*-}"
        printf '%s-%s' \
            "$(add_trailing_semantic_version_zeros "$base")" \
            "${prerelease//./+}"
        return
    fi

    printf '%s' "$(add_trailing_semantic_version_zeros "$version")"
}

build_updated_metadata() {
    local metadata_file="$1"
    local output_file="$2"
    local normalized_version="$3"
    local updated_at="$4"

    jq \
        --arg version "$normalized_version" \
        --arg updated_at "$updated_at" \
        '.releases = ((.releases // {}) | del(.[$version])) | .updated_at = $updated_at' \
        "$metadata_file" >"$output_file"
}

purge_package() {
    local swift_package_root="$1"
    local metadata_package_root="$2"
    local local_swift_package_root="$3"

    log "Purging package artifacts at ${swift_package_root}"
    rclone purge "$swift_package_root"

    log "Purging package metadata at ${metadata_package_root}"
    rclone purge "$metadata_package_root"

    purge_local_caches "$local_swift_package_root"
}

purge_version() {
    local swift_package_root="$1"
    local metadata_file="$2"
    local requested_version="$3"
    local local_swift_package_root="$4"
    local normalized_version
    local version_path
    local tmp_dir
    local downloaded_metadata_file
    local updated_metadata_file
    local updated_at
    local metadata_has_release="false"

    normalized_version="$(normalize_version "$requested_version")"
    version_path="${swift_package_root}/${normalized_version}"
    tmp_dir="$(mktemp -d)"
    downloaded_metadata_file="${tmp_dir}/index.json"
    updated_metadata_file="${tmp_dir}/index.updated.json"
    cleanup_paths+=("$tmp_dir")

    log "Requested version: ${requested_version}"
    log "Normalized storage version: ${normalized_version}"
    log "Fetching metadata from ${metadata_file}"

    if ! rclone cat "$metadata_file" >"$downloaded_metadata_file"; then
        fail "Unable to read metadata file ${metadata_file}"
    fi

    if ! jq empty "$downloaded_metadata_file" >/dev/null 2>&1; then
        fail "Metadata file ${metadata_file} is not valid JSON"
    fi

    if jq -e --arg version "$normalized_version" '.releases[$version] != null' "$downloaded_metadata_file" >/dev/null; then
        metadata_has_release="true"
        log "Version ${normalized_version} exists in metadata and will be removed"
    else
        warn "Version ${normalized_version} is not present in metadata; only registry files will be purged"
    fi

    log "Purging version artifacts at ${version_path}"
    rclone purge "$version_path"

    if [[ "$metadata_has_release" == "true" ]]; then
        updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        build_updated_metadata "$downloaded_metadata_file" "$updated_metadata_file" "$normalized_version" "$updated_at"

        log "Uploading updated metadata to ${metadata_file}"
        rclone copyto "$updated_metadata_file" "$metadata_file"
    else
        log "Skipping metadata upload because there was no release entry to remove"
    fi

    purge_local_caches "${local_swift_package_root}/${normalized_version}"
}

main() {
    local normalized_scope
    local normalized_name
    local swift_package_root
    local metadata_package_root
    local local_swift_package_root

    if [[ "$#" -ne 1 && "$#" -ne 2 ]]; then
        usage
    fi

    check_rclone_configuration
    parse_package "$1"

    normalized_scope="$(normalize_scope "$raw_scope")"
    normalized_name="$(normalize_name "$raw_name")"
    swift_package_root="${REGISTRY_ROOT}/registry/swift/${normalized_scope}/${normalized_name}"
    metadata_package_root="${REGISTRY_ROOT}/registry/metadata/${normalized_scope}/${normalized_name}"
    local_swift_package_root="${LOCAL_REGISTRY_ROOT}/${normalized_scope}/${normalized_name}"

    log "Package input: ${raw_scope}/${raw_name}"
    log "Normalized storage package: ${normalized_scope}/${normalized_name}"

    if [[ "$#" -eq 1 ]]; then
        purge_package "$swift_package_root" "$metadata_package_root" "$local_swift_package_root"
    else
        purge_version "$swift_package_root" "${metadata_package_root}/index.json" "$2" "$local_swift_package_root"
    fi

    log "Registry purge completed"
}

main "$@"
