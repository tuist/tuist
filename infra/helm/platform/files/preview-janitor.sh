#!/bin/sh
set -eu

: "${KURA_NAMESPACE:?KURA_NAMESPACE is required}"
: "${STUCK_CREATE_AGE_SECONDS:?STUCK_CREATE_AGE_SECONDS is required}"
: "${TEARDOWN_TIMEOUT:?TEARDOWN_TIMEOUT is required}"

preview_file="$(mktemp "${TMPDIR:-/tmp}/preview-janitor.XXXXXX")"
namespace_file="$(mktemp "${TMPDIR:-/tmp}/preview-janitor-namespaces.XXXXXX")"
failures=0

cleanup() {
  rm -f "$namespace_file" "$preview_file"
}
trap cleanup EXIT

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

is_uint() {
  case "$1" in
    "" | *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

preview_field() {
  printf '%s\n' "$1" | jq -r "$2"
}

load_previews() {
  kubectl get namespaces -l tuist.dev/preview=true -o json > "$namespace_file"
  jq -c '
    .items[] |
    {
      name: .metadata.name,
      release: (.metadata.labels["tuist.dev/release"] // ""),
      expires_at: (.metadata.labels["tuist.dev/expires-at"] // ""),
      state: (.metadata.labels["tuist.dev/state"] // ""),
      created_at: (.metadata.annotations["tuist.dev/created-at"] // "")
    }
  ' "$namespace_file" > "$preview_file"
}

print_previews() {
  log "Found preview namespaces:"
  jq -r '[.name, .release, .expires_at, .state, .created_at] | @tsv' "$preview_file"
}

release_name_for() {
  release="$1"
  namespace="$2"

  if [ -n "$release" ]; then
    printf '%s\n' "$release"
    return
  fi

  printf '%s\n' "${namespace#preview-}"
}

delete_preview() {
  namespace="$1"
  release="$2"
  reason="$3"

  log "==> Deleting: $namespace ($reason)"

  if ! kubectl -n "$KURA_NAMESPACE" delete kurainstance "${release}-kura" --ignore-not-found --wait=true --timeout "$TEARDOWN_TIMEOUT"; then
    warn "failed to delete KuraInstance ${KURA_NAMESPACE}/${release}-kura; continuing to Helm uninstall"
  fi

  if ! helm uninstall "$release" --namespace "$namespace" --wait --timeout "$TEARDOWN_TIMEOUT"; then
    warn "failed to uninstall Helm release $namespace/$release; continuing to namespace deletion"
  fi

  if ! kubectl delete namespace "$namespace" --ignore-not-found --wait=true --timeout "$TEARDOWN_TIMEOUT"; then
    warn "failed to delete namespace $namespace"
    return 1
  fi
}

delete_reason_for() {
  state="$1"
  created_at="$2"
  expires_at="$3"
  now="$4"

  if [ "$state" = "creating" ]; then
    if is_uint "$created_at" && [ $((now - created_at)) -ge "$STUCK_CREATE_AGE_SECONDS" ]; then
      printf 'stuck creating %ss, past STUCK_CREATE_AGE_SECONDS=%s\n' "$((now - created_at))" "$STUCK_CREATE_AGE_SECONDS"
      return 0
    fi

    return 1
  fi

  if is_uint "$expires_at" && [ "$expires_at" -le "$now" ]; then
    printf 'expired %ss ago\n' "$((now - expires_at))"
    return 0
  fi

  return 1
}

handle_preview() {
  preview="$1"
  now="$2"

  namespace="$(preview_field "$preview" '.name')"
  release="$(release_name_for "$(preview_field "$preview" '.release')" "$namespace")"
  expires_at="$(preview_field "$preview" '.expires_at')"
  state="$(preview_field "$preview" '.state')"
  created_at="$(preview_field "$preview" '.created_at')"

  if [ "$state" = "creating" ] && ! is_uint "$created_at"; then
    log "    Skipping mid-create: $namespace"
    return
  fi

  if [ "$state" != "creating" ] && ! is_uint "$expires_at"; then
    warn "namespace $namespace has missing or invalid expires-at label; skipping"
    return
  fi

  if reason="$(delete_reason_for "$state" "$created_at" "$expires_at" "$now")"; then
    if ! delete_preview "$namespace" "$release" "$reason"; then
      failures=$((failures + 1))
    fi
    return
  fi

  if [ "$state" = "creating" ]; then
    log "    Skipping mid-create: $namespace"
  else
    log "    Live: $namespace (expires in $((expires_at - now))s)"
  fi
}

main() {
  now="$(date +%s)"

  load_previews
  if [ ! -s "$preview_file" ]; then
    log "No preview namespaces found."
    return
  fi

  print_previews

  while IFS= read -r preview; do
    [ -z "$preview" ] && continue
    handle_preview "$preview" "$now"
  done < "$preview_file"

  if [ "$failures" -gt 0 ]; then
    warn "$failures preview namespace deletion(s) failed"
    return 1
  fi
}

main "$@"
