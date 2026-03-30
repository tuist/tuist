#!/usr/bin/env bash
#MISE description="Trigger a registry sync for a Swift package version on a production cache node"
#USAGE arg "<package>" help="Package in scope/name format (e.g., onevcat/rainbow)"
#USAGE arg "<version>" help="Version tag to sync (e.g., 4.2.1)"

set -euo pipefail

readonly DEPLOY_CONFIG="${MISE_PROJECT_ROOT}/cache/config/deploy.production.yml"

log()  { printf '[registry:sync] %s\n' "$*"; }
fail() { printf '[registry:sync] ERROR: %s\n' "$*" >&2; exit 1; }

# -- package parsing -----------------------------------------------------------

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

    if [[ ! "$raw_scope" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ ! "$raw_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        fail "Package scope and name must only contain alphanumeric characters, dots, hyphens, and underscores"
    fi
}

normalize_scope() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# -- host discovery ------------------------------------------------------------

read_random_production_host() {
    local hosts=()

    if [[ ! -f "$DEPLOY_CONFIG" ]]; then
        fail "Missing production deploy config: ${DEPLOY_CONFIG}"
    fi

    mapfile -t hosts < <(yq '.servers.web.hosts[]' "$DEPLOY_CONFIG")

    if [[ "${#hosts[@]}" -eq 0 ]]; then
        fail "No production cache hosts found in ${DEPLOY_CONFIG}"
    fi

    printf '%s' "${hosts[$((RANDOM % ${#hosts[@]}))]}"
}

# -- main ----------------------------------------------------------------------

main() {
    local package="$usage_package"
    local version="$usage_version"
    local normalized_scope
    local repository_full_handle
    local selected_host

    parse_package "$package"

    if [[ ! "$version" =~ ^[a-zA-Z0-9._+-]+$ ]]; then
        fail "Version must only contain alphanumeric characters, dots, hyphens, underscores, and plus signs"
    fi

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

log()  { printf '[registry:sync.remote:%s] %s\n' "$(hostname)" "$*"; }
fail() { printf '[registry:sync.remote:%s] ERROR: %s\n' "$(hostname)" "$*" >&2; exit 1; }

[[ "$scope" =~ ^[a-z0-9._-]+$ ]] || fail "Invalid scope: ${scope}"
[[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]] || fail "Invalid name: ${name}"
[[ "$repository_full_handle" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]] || fail "Invalid repository handle: ${repository_full_handle}"
[[ "$tag" =~ ^[a-zA-Z0-9._+-]+$ ]] || fail "Invalid tag: ${tag}"

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

main
