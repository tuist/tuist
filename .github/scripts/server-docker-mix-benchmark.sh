#!/usr/bin/env bash
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
cache="${RUNNER_TEMP:?}/server-docker-mix-cache"
registry="ghcr.io/${GITHUB_REPOSITORY,,}-mix-benchmark"
ref="$registry:${GITHUB_RUN_ID:?}"
before="$RUNNER_TEMP/before.Dockerfile"

# Both Dockerfiles build the exact same checkout. Only the build strategy differs.
[[ "${TUIST_BENCHMARK_BASELINE:?}" =~ ^[0-9a-f]{40}$ ]]
git fetch --depth=1 origin "$TUIST_BENCHMARK_BASELINE"
git show FETCH_HEAD:server/Dockerfile > "$before"
git show FETCH_HEAD:server/Dockerfile.dockerignore > "$before.dockerignore"

common=(
  --progress=plain
  --secret 'id=github_token,env=GITHUB_TOKEN'
  --build-arg MIX_ENV=prod
  --build-arg TUIST_HOSTED=1
  --build-arg TUIST_VERSION=benchmark
)

build_image() {
  local variant="$1" phase="$2" file
  local args=()
  if [[ "$variant" == before ]]; then
    file="$before"
  else
    file=server/Dockerfile
    args+=(--build-context "mix-cache=$cache/current")
  fi
  docker buildx build "${common[@]}" "${args[@]}" \
    --file "$file" --target runner --push \
    --build-arg "APT_CACHE_BUST=$phase-$GITHUB_RUN_ID" \
    --cache-from "type=registry,ref=$ref-seed-$variant" \
    --cache-to "type=registry,ref=$ref-$phase-$variant,mode=max" \
    --tag "$ref-$phase-$variant-image" .
}

export_mix() {
  docker buildx build "${common[@]}" \
    --file server/Dockerfile --target mix-cache-export \
    --build-context "mix-cache=$cache/current" \
    --output "type=local,dest=$cache/next" .
}

case "${1:-}" in
  seed)
    rm -rf "$cache/current"
    bash "$scripts/server-docker-mix-cache.sh" prepare
    # The first seeding build can read the real cache but never modifies it.
    docker buildx build "${common[@]}" --file "$before" --target runner --push \
      --build-arg "APT_CACHE_BUST=seed-$GITHUB_RUN_ID" \
      --cache-from "type=registry,ref=ghcr.io/$GITHUB_REPOSITORY-buildcache:server" \
      --cache-to "type=registry,ref=$ref-seed-before,mode=max" \
      --tag "$ref-seed-before-image" .
    build_image after seed
    export_mix
    TUIST_MIX_CACHE_EXPORTED=true bash "$scripts/server-docker-mix-cache.sh" commit
    ;;
  measure)
    variant="${TUIST_BENCHMARK_VARIANT:?}"
    [[ "$variant" == before || "$variant" == after ]]
    # A controlled, identical source change invalidates the app layer in both cases.
    # It does not change dependency manifests or the runtime security-refresh policy.
    probe=server/lib/tuist/cache_benchmark_probe.ex
    test ! -e "$probe"
    trap 'rm -f "$probe"' EXIT
    printf 'defmodule Tuist.CacheBenchmarkProbe do\n  def value, do: :benchmark\nend\n' > "$probe"
    build_started="$(date +%s)"
    build_image "$variant" measured 2>&1 | tee "$RUNNER_TEMP/build.log"
    build_finished="$(date +%s)"
    export_seconds=0
    if [[ "$variant" == after ]]; then
      export_started="$(date +%s)"
      export_mix
      original="$cache/current/_build/prod/lib/tuist/ebin/Elixir.Tuist.Environment.beam"
      restored="$cache/next/_build/prod/lib/tuist/ebin/Elixir.Tuist.Environment.beam"
      cmp "$original" "$restored"
      test ! "$original" -nt "$restored"
      test ! "$original" -ot "$restored"
      test -f "$cache/next/_build/prod/lib/tuist/ebin/Elixir.Tuist.CacheBenchmarkProbe.beam"
      TUIST_MIX_CACHE_EXPORTED=true bash "$scripts/server-docker-mix-cache.sh" commit
      export_seconds=$(( $(date +%s) - export_started ))
    fi
    jq -n --arg variant "$variant" \
      --argjson build_seconds "$((build_finished - build_started))" \
      --argjson export_seconds "$export_seconds" \
      --argjson foreground_seconds "$(( $(date +%s) - TUIST_BENCHMARK_STARTED ))" \
      '{variant: $variant, build_seconds: $build_seconds, mix_export_seconds: $export_seconds, foreground_seconds: $foreground_seconds}' \
      | tee "$RUNNER_TEMP/result.json"
    printf 'image=%s-measured-%s-image\n' "$ref" "$variant" >> "$GITHUB_OUTPUT"
    ;;
  *)
    echo 'Usage: server-docker-mix-benchmark.sh seed|measure' >&2
    exit 1
    ;;
esac
