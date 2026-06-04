#!/usr/bin/env bash
#MISE description="Trigger a registry sync for a Swift package version on the production Swift registry"
#USAGE arg "<package>" help="Package in scope/name format (e.g., onevcat/rainbow)"
#USAGE arg "<version>" help="Version tag to sync (e.g., 4.2.1)"

set -euo pipefail

readonly KUBE_NAMESPACE="${TUIST_SWIFT_REGISTRY_NAMESPACE:-swift-registry}"
readonly KUBE_CONTEXT="${TUIST_SWIFT_REGISTRY_KUBE_CONTEXT:-}"
readonly APP_SELECTOR="app.kubernetes.io/instance=swift-registry,app.kubernetes.io/component=app"

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

# -- Kubernetes helpers --------------------------------------------------------

kubectl_registry() {
    local args=(kubectl)

    if [[ -n "$KUBE_CONTEXT" ]]; then
        args+=(--context "$KUBE_CONTEXT")
    fi

    "${args[@]}" -n "$KUBE_NAMESPACE" "$@"
}

read_random_registry_pod() {
    local pods=()

    while IFS= read -r pod; do
        [[ -n "$pod" ]] && pods+=("$pod")
    done < <(kubectl_registry get pods -l "$APP_SELECTOR" -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}')

    if [[ "${#pods[@]}" -eq 0 ]]; then
        fail "No running Swift registry pods found in namespace ${KUBE_NAMESPACE}"
    fi

    printf '%s' "${pods[$((RANDOM % ${#pods[@]}))]}"
}

# -- main ----------------------------------------------------------------------

main() {
    local package="$usage_package"
    local version="$usage_version"
    local normalized_scope
    local repository_full_handle
    local selected_pod

    parse_package "$package"

    if [[ ! "$version" =~ ^[a-zA-Z0-9._+-]+$ ]]; then
        fail "Version must only contain alphanumeric characters, dots, hyphens, underscores, and plus signs"
    fi

    normalized_scope="$(normalize_scope "$raw_scope")"
    repository_full_handle="${raw_scope}/${raw_name}"
    selected_pod="$(read_random_registry_pod)"

    log "Package input: ${raw_scope}/${raw_name}"
    log "Using scope \"${normalized_scope}\", name \"${raw_name}\", tag \"${version}\""
    log "Using pod ${selected_pod} in namespace ${KUBE_NAMESPACE}"
    log "Enqueueing SwiftRegistry.Registry.ReleaseWorker for ${repository_full_handle}@${version}"

elixir_code=$(cat <<EOF
args = %{
  "scope" => "${normalized_scope}",
  "name" => "${raw_name}",
  "repository_full_handle" => "${repository_full_handle}",
  "tag" => "${version}"
}

case args |> SwiftRegistry.Registry.ReleaseWorker.new() |> Oban.insert() do
  {:ok, job} ->
    IO.puts("Enqueued Oban job " <> Integer.to_string(job.id))

  {:error, reason} ->
    raise "Failed to enqueue SwiftRegistry.Registry.ReleaseWorker: #{inspect(reason)}"
end
EOF
)

    kubectl_registry exec "$selected_pod" -- /app/bin/swift_registry rpc "$elixir_code"

    log "Registry sync request completed"
}

main
