#!/usr/bin/env bash
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
cache="${RUNNER_TEMP:?}/server-docker-mix-cache"
registry="ghcr.io/${GITHUB_REPOSITORY,,}-mix-benchmark"
ref="$registry:${GITHUB_RUN_ID:?}"

common=(
  --progress=plain
  --secret 'id=github_token,env=GITHUB_TOKEN'
  --build-arg MIX_ENV=prod
  --build-arg TUIST_HOSTED=1
  --build-arg TUIST_VERSION=benchmark
)

build_image() {
  local variant="$1" phase="$2" source
  local args=()
  if [[ "$variant" == after ]]; then
    args+=(--build-context "mix-cache=$cache/current")
  fi
  if [[ "$phase" == seed ]]; then
    source="ghcr.io/$GITHUB_REPOSITORY-buildcache:server"
  else
    source="$ref-seed-before"
  fi
  docker buildx build "${common[@]}" "${args[@]}" \
    --file server/Dockerfile --target runner --push \
    --build-arg "APT_CACHE_BUST=$phase-$GITHUB_RUN_ID" \
    --cache-from "type=registry,ref=$source" \
    --cache-to "type=registry,ref=$ref-$phase-$variant,mode=max" \
    --tag "$ref-$phase-$variant-image" .
}

export_mix() {
  local args=()
  if [[ "$1" == after ]]; then
    args+=(--build-context "mix-cache=$cache/current")
  fi
  docker buildx build "${common[@]}" "${args[@]}" \
    --file server/Dockerfile --target mix-cache-export \
    --output "type=local,dest=$cache/next" .
}

case "${1:-}" in
  seed)
    rm -rf "$cache/current"
    bash "$scripts/server-docker-mix-cache.sh" prepare
    # Both consumers use this exact registry cache; only after adds Mix state.
    build_image before seed
    export_mix before
    TUIST_MIX_CACHE_EXPORTED=true bash "$scripts/server-docker-mix-cache.sh" commit
    printf '%s\n' "$GITHUB_RUN_ID" > "$cache/current/.run-id"
    ;;
  measure)
    variant="${TUIST_BENCHMARK_VARIANT:?}"
    [[ "$variant" == before || "$variant" == after ]]
    # Same Dockerfile and one identical source change: this isolates Mix reuse,
    # not the separate Swift artifact-stage optimization included in both cases.
    probe=server/lib/tuist/cache_benchmark_probe.ex
    test ! -e "$probe"
    trap 'rm -f "$probe"' EXIT
    printf 'defmodule Tuist.CacheBenchmarkProbe do\n  def value, do: :benchmark\nend\n' > "$probe"
    build_started="$(date +%s)"
    build_image "$variant" measured 2>&1 | tee "$RUNNER_TEMP/build.log"
    build_finished="$(date +%s)"
    export_seconds=0
    snapshot_bytes=0
    if [[ "$variant" == after ]]; then
      export_started="$(date +%s)"
      export_mix after
      original="$cache/current/_build/tuist/ebin/Elixir.Tuist.Environment.beam"
      restored="$cache/next/_build/tuist/ebin/Elixir.Tuist.Environment.beam"
      cmp "$original" "$restored"
      test ! "$original" -nt "$restored"
      test ! "$original" -ot "$restored"
      test -f "$cache/next/_build/tuist/ebin/Elixir.Tuist.CacheBenchmarkProbe.beam"
      TUIST_MIX_CACHE_EXPORTED=true bash "$scripts/server-docker-mix-cache.sh" commit
      export_seconds=$(( $(date +%s) - export_started ))
      snapshot_bytes="$(du -sb "$cache/current" | cut -f1)"
    fi
    awk '
      /^#[0-9]+ \[/ {
        if (/mix deps.get/) phase[$1] = "deps_get"
        if (/mix deps.compile/) phase[$1] = "deps_compile"
        if (/prefetch-locale-data.sh/) phase[$1] = "cldr_prefetch"
        if (/mix compile --warnings-as-errors/) phase[$1] = "app_compile_including_restore"
        if (/APT_CACHE_BUST/) phase[$1] = "runtime_package_refresh"
      }
      /^#[0-9]+ exporting cache to registry/ { phase[$1] = "registry_cache_export" }
      phase[$1] != "" && ($2 == "DONE" || $2 == "CACHED") {
        printf "%s\t%s\t%.3f\n", phase[$1], ($2 == "CACHED" ? "cached" : "executed"), ($2 == "CACHED" ? 0 : $3 + 0)
      }
    ' "$RUNNER_TEMP/build.log" > "$RUNNER_TEMP/vertices.tsv"
    jq -n --arg variant "$variant" \
      --argjson build_seconds "$((build_finished - build_started))" \
      --argjson export_seconds "$export_seconds" \
      --argjson snapshot_bytes "$snapshot_bytes" \
      --argjson foreground_seconds "$(( $(date +%s) - TUIST_BENCHMARK_STARTED ))" \
      --rawfile vertices "$RUNNER_TEMP/vertices.tsv" \
      '{variant: $variant, build_seconds: $build_seconds, mix_export_seconds: $export_seconds, snapshot_bytes: $snapshot_bytes, foreground_seconds: $foreground_seconds,
        vertices: ($vertices | split("\n") | map(select(length > 0) | split("\t") | {phase: .[0], status: .[1], seconds: (.[2] | tonumber)}))}' \
      | tee "$RUNNER_TEMP/result.json"
    printf 'image=%s-measured-%s-image\n' "$ref" "$variant" >> "$GITHUB_OUTPUT"
    ;;
  *)
    echo 'Usage: server-docker-mix-benchmark.sh seed|measure' >&2
    exit 1
    ;;
esac
