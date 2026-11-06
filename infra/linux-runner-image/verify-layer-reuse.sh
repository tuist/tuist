#!/usr/bin/env bash
# Run after exporting the unmodified build as an OCI archive and local cache.
# Checks the bytes a node actually downloads, not just BuildKit cache messages.
set -euo pipefail
baseline="${1:?baseline OCI archive required}"
cache="${2:?exported BuildKit cache directory required}"
build_args=()
if [[ -n "${3:-}" ]]; then build_args+=(--build-arg "RUNNER_VERSION=$3"); fi
source_dir="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
builder="linux-layer-check-$$-$RANDOM"
cleanup() {
  docker buildx rm "$builder" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
mkdir "$work/before" "$work/after"
cp -R "$source_dir" "$work/context"
printf '\n# Layer-reuse regression probe.\n' >> "$work/context/dispatch-poll.sh"
docker buildx create --name "$builder" --driver docker-container
docker buildx build --builder "$builder" --platform linux/amd64 --progress plain \
  "${build_args[@]}" \
  --build-context "certificate-trust=$source_dir/../certificate-trust" \
  --cache-from "type=local,src=$cache" \
  --output "type=oci,dest=$work/after.tar" "$work/context"
tar -xf "$baseline" -C "$work/before"
tar -xf "$work/after.tar" -C "$work/after"
node "$source_dir/compare-layers.mjs" "$work/before" "$work/after"
