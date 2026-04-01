#!/usr/bin/env bash
#MISE description="Purge a production cache artifact from all cache nodes and Tigris"
#USAGE arg "<fullhandle>" help="Artifact handle in account/project format (e.g., example-org/example-project)"
#USAGE arg "<type>" help="Artifact type" {
#USAGE   choices "module"
#USAGE }
#USAGE arg "<hash>" help="Artifact hash (e.g., d4f9a2c16b7e43e8a1c0d95fb62e1347)"

set -euo pipefail

readonly DEPLOY_CONFIG="${MISE_PROJECT_ROOT}/config/deploy.production.yml"
readonly LOCAL_STORAGE_ROOT="/cas"
readonly RCLONE_REMOTE="tigris"
readonly CACHE_BUCKET="tuist-cas-production"
readonly CACHE_ROOT="${RCLONE_REMOTE}:${CACHE_BUCKET}"

log()  { printf '[cache:purge] %s\n' "$*"; }
warn() { printf '[cache:purge] WARNING: %s\n' "$*" >&2; }
fail() { printf '[cache:purge] ERROR: %s\n' "$*" >&2; exit 1; }

# -- input parsing --------------------------------------------------------------

parse_fullhandle() {
    local fullhandle="$1"

    if [[ "$fullhandle" != */* ]]; then
        fail "fullhandle must be in account/project format"
    fi

    raw_account_handle="${fullhandle%%/*}"
    raw_project_handle="${fullhandle#*/}"

    if [[ -z "$raw_account_handle" || -z "$raw_project_handle" || "$raw_project_handle" == */* ]]; then
        fail "fullhandle must be in account/project format"
    fi

    if [[ ! "$raw_account_handle" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ ! "$raw_project_handle" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        fail "fullhandle segments must only contain alphanumeric characters, dots, hyphens, and underscores"
    fi
}

parse_type() {
    local type="$1"

    case "$type" in
        module)
            artifact_category_path="module/builds"
            ;;
        *)
            fail "Unsupported type: ${type}. Only \"module\" is currently allowed"
            ;;
    esac
}

parse_hash() {
    local hash="$1"

    if [[ ! "$hash" =~ ^[A-Fa-f0-9]{4,}$ ]]; then
        fail "hash must be a hex string with at least 4 characters"
    fi

    artifact_hash="$hash"
    shard1="${artifact_hash:0:2}"
    shard2="${artifact_hash:2:2}"
}

# -- rclone configuration check -----------------------------------------------

print_rclone_setup_instructions() {
    cat >&2 <<EOF
[cache:purge] ERROR: rclone remote "${RCLONE_REMOTE}" is not configured.

Set it up with the production cache Tigris credentials from 1Password/Kamal secrets:
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
  rclone lsf ${CACHE_ROOT}/ | head
EOF
}

check_rclone_configuration() {
    local remotes

    log "Checking rclone remote configuration"
    remotes="$(rclone listremotes 2>/dev/null || true)"

    if ! grep -Fxq "${RCLONE_REMOTE}:" <<<"$remotes"; then
        print_rclone_setup_instructions
        exit 1
    fi

    log "Found rclone remote \"${RCLONE_REMOTE}\""
    log "Verifying read access to ${CACHE_ROOT}"

    if ! rclone lsf "${CACHE_ROOT}/" >/dev/null 2>&1; then
        fail "Unable to read ${CACHE_ROOT}. Check the configured ${RCLONE_REMOTE} credentials."
    fi
}

# -- host discovery -------------------------------------------------------------

read_all_production_hosts() {
    local hosts

    if [[ ! -f "$DEPLOY_CONFIG" ]]; then
        fail "Missing production deploy config: ${DEPLOY_CONFIG}"
    fi

    hosts="$(yq '.servers.web.hosts[]' "$DEPLOY_CONFIG")"

    if [[ -z "$hosts" ]]; then
        fail "No production cache hosts found in ${DEPLOY_CONFIG}"
    fi

    printf '%s\n' "$hosts"
}

# -- purge operations -----------------------------------------------------------

remote_prefix_state() {
    local remote_path="$1"
    local output

    if output="$(rclone lsf "$remote_path" 2>&1)"; then
        if [[ -n "$output" ]]; then
            printf 'present'
        else
            printf 'absent'
        fi

        return 0
    fi

    case "$output" in
        *"directory not found"*|*"Directory not found"*|*"not found"*|*"Not Found"*|*"doesn't exist"*)
            printf 'absent'
            return 0
            ;;
        *)
            warn "rclone lsf failed for ${remote_path}: ${output}"
            return 1
            ;;
    esac
}

purge_local_caches() {
    local local_path="$1"
    local hosts=()
    local host
    local status
    local failed_hosts=()

    mapfile -t hosts < <(read_all_production_hosts)

    log "Purging local cache path from ${#hosts[@]} production nodes"

    for host in "${hosts[@]}"; do
        if ssh -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR "$host" "sudo test -e \"$local_path\""; then
            log "Removing ${local_path} on ${host}"

            if ssh -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR "$host" "sudo rm -rf -- \"$local_path\"" && \
               ssh -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR "$host" "! sudo test -e \"$local_path\""; then
                log "Purged local cache on ${host}"
            else
                warn "Failed to purge local cache on ${host}"
                failed_hosts+=("$host")
            fi

            continue
        else
            status=$?
        fi

        if [[ "$status" -eq 1 ]]; then
            log "Local cache already absent on ${host}"
        else
            warn "Failed to inspect ${local_path} on ${host} (ssh exit ${status})"
            failed_hosts+=("$host")
        fi
    done

    if [[ "${#failed_hosts[@]}" -gt 0 ]]; then
        warn "Failed to purge local cache path on: ${failed_hosts[*]}"
        return 1
    fi

    return 0
}

purge_tigris_cache() {
    local remote_path="$1"
    local state

    state="$(remote_prefix_state "$remote_path")" || {
        warn "Unable to inspect Tigris path ${remote_path}"
        return 1
    }

    if [[ "$state" == "absent" ]]; then
        log "Tigris path already absent: ${remote_path}"
        return 0
    fi

    log "Purging Tigris path ${remote_path}"

    if ! rclone purge "$remote_path"; then
        warn "Failed to purge Tigris path ${remote_path}"
        return 1
    fi

    state="$(remote_prefix_state "$remote_path")" || {
        warn "Unable to verify Tigris path ${remote_path} after purge"
        return 1
    }

    if [[ "$state" != "absent" ]]; then
        warn "Tigris path still exists after purge: ${remote_path}"
        return 1
    fi

    log "Purged Tigris path ${remote_path}"

    return 0
}

# -- main -----------------------------------------------------------------------

main() {
    local fullhandle="$usage_fullhandle"
    local type="$usage_type"
    local hash="$usage_hash"
    local artifact_root
    local failed=0
    local local_path
    local remote_path

    parse_fullhandle "$fullhandle"
    parse_type "$type"
    parse_hash "$hash"
    check_rclone_configuration

    artifact_root="${raw_account_handle}/${raw_project_handle}/${artifact_category_path}/${shard1}/${shard2}/${artifact_hash}"
    local_path="${LOCAL_STORAGE_ROOT}/${artifact_root}"
    remote_path="${CACHE_ROOT}/${artifact_root}"

    log "Handle input: ${raw_account_handle}/${raw_project_handle}"
    log "Type: ${type}"
    log "Hash: ${artifact_hash}"
    log "Local cache path: ${local_path}"
    log "Tigris cache path: ${remote_path}"

    purge_local_caches "$local_path" || failed=1
    purge_tigris_cache "$remote_path" || failed=1

    if [[ "$failed" -ne 0 ]]; then
        fail "Cache purge finished with errors"
    fi

    log "Cache purge completed"
}

main
