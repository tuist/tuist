#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly DEPLOY_PRODUCTION_CONFIG_FILE="${PROJECT_ROOT}/cache/config/deploy.production.yml"

log() {
    printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

fail() {
    printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<EOF
Usage: ${SCRIPT_NAME} scope/name version

Examples:
  ${SCRIPT_NAME} onevcat/Rainbow 4.2.1
  ${SCRIPT_NAME} onevcat/Rainbow v2.0.0
EOF
    exit 1
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        fail "Missing required command: ${command_name}"
    fi
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

read_random_production_host() {
    local hosts=()
    local selected_index

    mapfile -t hosts < <(sed -n '/^[[:space:]]*hosts:[[:space:]]*$/,$ {
        /^[[:space:]]*hosts:/d
        /^[[:space:]]*-[[:space:]]/ { s/^[[:space:]]*-[[:space:]]*//; p; b; }
        /^[[:space:]]*$/b
        q
    }' "$DEPLOY_PRODUCTION_CONFIG_FILE")

    if [[ "${#hosts[@]}" -eq 0 ]]; then
        fail "Unable to determine any production cache hosts from ${DEPLOY_PRODUCTION_CONFIG_FILE}"
    fi

    selected_index=$((RANDOM % ${#hosts[@]}))
    printf '%s' "${hosts[$selected_index]}"
}

main() {
    local version
    local normalized_scope
    local repository_full_handle
    local selected_host

    if [[ "$#" -ne 2 ]]; then
        usage
    fi

    require_command ssh

    if [[ ! -f "$DEPLOY_PRODUCTION_CONFIG_FILE" ]]; then
        fail "Missing production deploy config file: ${DEPLOY_PRODUCTION_CONFIG_FILE}"
    fi

    parse_package "$1"
    version="$2"
    normalized_scope="$(normalize_scope "$raw_scope")"
    repository_full_handle="${raw_scope}/${raw_name}"
    selected_host="$(read_random_production_host)"

    log "Package input: ${raw_scope}/${raw_name}"
    log "Using scope \"${normalized_scope}\", name \"${raw_name}\", tag \"${version}\""
    log "Randomly selected production cache node from cache/config/deploy.production.yml: ${selected_host}"
    log "Connecting to ${selected_host}"

    ssh -o BatchMode=yes "$selected_host" bash -s -- "$normalized_scope" "$raw_name" "$repository_full_handle" "$version" <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail

scope="$1"
name="$2"
repository_full_handle="$3"
tag="$4"

log() {
    printf '[sync-registry-package.remote:%s] %s\n' "$(hostname)" "$*"
}

fail() {
    printf '[sync-registry-package.remote:%s] ERROR: %s\n' "$(hostname)" "$*" >&2
    exit 1
}

find_cache_container() {
    local container_name
    local image_name

    container_name="$(docker ps --filter 'label=service=cache' --filter 'label=role=web' --format '{{.Names}}' | head -n 1)"
    if [[ -n "$container_name" ]]; then
        printf '%s' "$container_name"
        return 0
    fi

    container_name="$(docker ps --filter 'label=service=cache' --format '{{.Names}}' | head -n 1)"
    if [[ -n "$container_name" ]]; then
        printf '%s' "$container_name"
        return 0
    fi

    while IFS='|' read -r container_name image_name; do
        case "$container_name" in
            cache-web*|cache-*)
                printf '%s' "$container_name"
                return 0
                ;;
        esac

        case "$image_name" in
            ghcr.io/*/cache|ghcr.io/*/cache:*|ghcr.io/*/cache@*|*/cache|*/cache:*|*/cache@*|cache|cache:*|cache@*)
                printf '%s' "$container_name"
                return 0
                ;;
        esac
    done < <(docker ps --format '{{.Names}}|{{.Image}}')

    return 1
}

log "Looking for the running cache container"
container="$(find_cache_container)" || fail "Could not find a running cache container"
log "Using container ${container}"
log "Enqueueing Cache.Registry.ReleaseWorker for ${repository_full_handle}@${tag}"

elixir_code=$(cat <<EOF
args = %{
  "scope" => "${scope}",
  "name" => "${name}",
  "repository_full_handle" => "${repository_full_handle}",
  "tag" => "${tag}"
}

case args |> Cache.Registry.ReleaseWorker.new() |> Oban.insert() do
  {:ok, job} ->
    IO.puts("Enqueued Oban job " <> Integer.to_string(job.id))

  {:error, reason} ->
    raise "Failed to enqueue Cache.Registry.ReleaseWorker: #{inspect(reason)}"
end
EOF
)

docker exec "$container" /app/bin/cache rpc "$elixir_code"

log "Worker enqueue request finished"
REMOTE

    log "Registry sync request completed"
}

main "$@"
