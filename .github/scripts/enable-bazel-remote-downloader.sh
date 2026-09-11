#!/usr/bin/env bash
set -euo pipefail

# Bridge CI's pinned CLI until its next release generates these options itself.
config="${1:-.bazelrc.tuist}"
endpoint="$(awk '/^build --remote_cache=/{sub(/^build --remote_cache=/, ""); print; exit}' "$config")"
[[ "$endpoint" == grpc://* || "$endpoint" == grpcs://* ]] || {
  echo "No gRPC cache endpoint in $config" >&2
  exit 1
}
has_option() {
  awk -v option="$1" '
    {sub(/#.*/, "")}
    $1 == "build" || $1 == "common" {
      for (i = 2; i <= NF; i++) if ($i == option || index($i, option "=") == 1) found = 1
    }
    END {exit !found}
  ' "$config"
}
if ! has_option --experimental_remote_downloader; then
  printf '\nbuild --experimental_remote_downloader=%s\n' "$endpoint" >> "$config"
  if ! has_option --experimental_remote_downloader_local_fallback &&
     ! has_option --noexperimental_remote_downloader_local_fallback; then
    printf 'build --experimental_remote_downloader_local_fallback=true\n' >> "$config"
  fi
fi
