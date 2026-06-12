#!/usr/bin/env bash
#MISE description="Trigger a registry sync for a Swift package version on the registry service"
#USAGE arg "<package>" help="Package in scope/name format (e.g., onevcat/rainbow)"
#USAGE arg "<version>" help="Version tag to sync (e.g., 4.2.1)"
#USAGE flag "--namespace <namespace>" help="Kubernetes namespace (defaults to registry)"
#USAGE flag "--context <context>" help="kubectl context (defaults to current)"

set -euo pipefail

readonly DEFAULT_NAMESPACE="${TUIST_REGISTRY_NAMESPACE:-registry}"
readonly APP_SELECTOR="app.kubernetes.io/instance=registry,app.kubernetes.io/component=app"

log()  { printf '[registry:sync] %s\n' "$*"; }
fail() { printf '[registry:sync] ERROR: %s\n' "$*" >&2; exit 1; }

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

main() {
    local package="$usage_package"
    local version="$usage_version"
    local namespace="${usage_namespace:-$DEFAULT_NAMESPACE}"
    local context_flag=()
    local normalized_scope
    local repository_full_handle
    local pod

    if [[ -n "${usage_context:-}" ]]; then
        context_flag=(--context "${usage_context}")
    fi

    parse_package "$package"

    if [[ ! "$version" =~ ^[a-zA-Z0-9._+-]+$ ]]; then
        fail "Version must only contain alphanumeric characters, dots, hyphens, underscores, and plus signs"
    fi

    normalized_scope="$(normalize_scope "$raw_scope")"
    repository_full_handle="${raw_scope}/${raw_name}"

    log "Package input: ${raw_scope}/${raw_name}"
    log "Using scope \"${normalized_scope}\", name \"${raw_name}\", tag \"${version}\""
    log "Selecting a registry pod in namespace \"${namespace}\""

    pod="$(kubectl "${context_flag[@]}" -n "$namespace" get pod \
        -l "$APP_SELECTOR" \
        -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | awk '{print $1}')"

    if [[ -z "$pod" ]]; then
        fail "No running registry pod found in namespace ${namespace} matching ${APP_SELECTOR}"
    fi

    log "Using pod ${pod}"
    log "Enqueueing TuistRegistry.Swift.ReleaseWorker for ${repository_full_handle}@${version}"

    elixir_code=$(cat <<EOF
args = %{
  "scope" => "${normalized_scope}",
  "name" => "${raw_name}",
  "repository_full_handle" => "${repository_full_handle}",
  "tag" => "${version}"
}

case args |> TuistRegistry.Swift.ReleaseWorker.new() |> Oban.insert() do
  {:ok, job} ->
    IO.puts("Enqueued Oban job " <> Integer.to_string(job.id))

  {:error, reason} ->
    raise "Failed to enqueue TuistRegistry.Swift.ReleaseWorker: #{inspect(reason)}"
end
EOF
)

    kubectl "${context_flag[@]}" -n "$namespace" exec -c registry "$pod" -- \
        /app/bin/tuist_registry rpc "$elixir_code"

    log "Worker enqueue request finished"
}

main
