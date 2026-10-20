#!/usr/bin/env bash
set -euo pipefail

action_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixtures="$(mktemp -d)"
prefix="cache-volume-test-${GITHUB_RUN_ID:-local}-$$"
registry_name="$prefix-registry"
cache_root="${RUNNER_TEMP:?}/docker-build-cache"

cleanup() {
  for phase in cold warm changed registry; do
    docker buildx rm "$prefix-$phase" >/dev/null 2>&1 || true
  done
  docker rm -f "$registry_name" >/dev/null 2>&1 || true
  rm -rf "$fixtures"
}
trap cleanup EXIT

docker run --detach --name "$registry_name" --publish 127.0.0.1::5000 registry:3
registry_address="$(docker port "$registry_name" 5000/tcp)"
export TUIST_DOCKER_REGISTRY_CACHE="$registry_address/cache:smoke"
export TUIST_DOCKER_CACHE_DIRECTORY="$cache_root"
buildkit_config="$fixtures/buildkitd.toml"
printf '[registry."%s"]\n  http = true\n' "$registry_address" > "$buildkit_config"

ready=false
for _attempt in {1..30}; do
  if curl --fail --silent --max-time 2 "http://$registry_address/v2/" >/dev/null; then
    ready=true
    break
  fi
  sleep 1
done
if [ "$ready" != true ]; then
  echo 'Test registry did not become ready.' >&2
  exit 1
fi

mkdir -p "$fixtures/context"
printf 'FROM scratch\nCOPY input /input\n' > "$fixtures/context/Dockerfile"
printf 'first input: %s\n' "$prefix" > "$fixtures/context/input"

build() {
  local phase="$1"
  local builder="$prefix-$phase"
  local outputs="$fixtures/$phase.outputs"
  local log="$fixtures/$phase.log"
  local cache_from line
  local cache_args=()

  GITHUB_OUTPUT="$outputs" bash "$action_dir/prepare.sh"
  cache_from="$(grep '^cache-from=' "$outputs")"
  cache_from="${cache_from#cache-from=}"
  while IFS= read -r line; do
    case "$line" in
      type=*) cache_args+=(--cache-to "$line") ;;
    esac
  done < "$outputs"

  docker buildx create --name "$builder" --driver docker-container \
    --driver-opt network=host --buildkitd-config "$buildkit_config"
  if ! docker buildx build --builder "$builder" --progress plain \
    --cache-from "$cache_from" "${cache_args[@]}" \
    --output "type=local,dest=$fixtures/$phase-output" \
    "$fixtures/context" > "$log" 2>&1; then
    tail -100 "$log" >&2
    return 1
  fi
  cmp "$fixtures/context/input" "$fixtures/$phase-output/input"
  bash "$action_dir/commit.sh"
  test -s "$cache_root/current/index.json"
  docker buildx rm "$builder"
}

copy_was_cached() {
  awk '/#[0-9]+ \[.*\] COPY input \/input/ { id = $1 }
       id != "" && $1 == id && $2 == "CACHED" { found = 1 }
       END { exit !found }' "$1"
}

# This test exercises fresh workers in one job, not cross-job volume publication.
rm -rf -- "$cache_root/current" "$cache_root/next"
build cold
build warm
if ! copy_was_cached "$fixtures/warm.log"; then
  tail -100 "$fixtures/warm.log" >&2
  echo 'Fresh worker did not reuse the local COPY layer.' >&2
  exit 1
fi

printf 'changed input: %s\n' "$prefix" > "$fixtures/context/input"
build changed
if copy_was_cached "$fixtures/changed.log"; then
  echo 'Changed input incorrectly reused the old COPY layer.' >&2
  exit 1
fi

# The registry fallback must also contain the latest successfully exported graph.
rm -rf -- "$cache_root/current"
build registry
if ! copy_was_cached "$fixtures/registry.log"; then
  tail -100 "$fixtures/registry.log" >&2
  echo 'Fresh worker did not reuse the registry COPY layer.' >&2
  exit 1
fi

echo 'Fresh-worker local import, source invalidation and registry fallback passed.'
