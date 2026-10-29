#!/usr/bin/env bash
# Reproduce two consecutive releases before/after this change, then measure
# updates in disposable Docker daemons. Never prune the host's image store.
set -euo pipefail
base="${BENCHMARK_BASE_SHA:?baseline commit required}"
output="${BENCHMARK_OUTPUT:?output directory required}"
experiment="${BENCHMARK_EXPERIMENT:?unique run identifier required}"
repository=ghcr.io/tuist/tuist-linux-runner
[[ "$experiment" =~ ^[a-z0-9-]+$ ]] || exit 1
git cat-file -e "${base}^{commit}"
mkdir -p "$output"
work="$(mktemp -d)"
builder=""
daemon=""
volume=""
cleanup() {
  [[ -z "$daemon" ]] || docker rm -f "$daemon" >/dev/null 2>&1 || true
  [[ -z "$volume" ]] || docker volume rm "$volume" >/dev/null 2>&1 || true
  [[ -z "$builder" ]] || docker buildx rm "$builder" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$work/before" "$work/after"
git archive "$base" infra/linux-runner-image | tar -x -C "$work/before"
git archive HEAD infra/linux-runner-image | tar -x -C "$work/after"
jq -n --arg base "$(git rev-parse "$base")" --arg head "$(git rev-parse HEAD)" \
  --arg experiment "$experiment" '{base:$base,head:$head,experiment:$experiment,
    platform:"linux/amd64",pullSamplesPerArm:3,
    methodology:"Fresh builder per build; old releases import no cache; new release update imports an isolated GHCR mode=max cache. Each pull sample uses a fresh Docker daemon, seeds the first image, then times the update including unpacking."}' > "$output/experiment.json"
docker version > "$output/docker-version.txt"
docker buildx version > "$output/buildx-version.txt"
df -h > "$output/disk-before.txt"
: > "$output/builds.jsonl"
: > "$output/pulls.jsonl"

build() {
  local arm="$1" phase="$2" context ref start finish digest manifest_digest
  local cache_args=()
  context="$work/$arm/infra/linux-runner-image"
  ref="$repository:bench-$experiment-$arm-$phase"
  if [[ "$phase" == update ]]; then
    printf '\n# Layer-reuse regression probe.\n' >> "$context/dispatch-poll.sh"
  fi
  if [[ "$arm" == after ]]; then
    cache_args+=(--cache-to "type=registry,ref=$repository:bench-$experiment-cache,mode=max")
    if [[ "$phase" == update ]]; then
      cache_args+=(--cache-from "type=registry,ref=$repository:bench-$experiment-cache")
    fi
  fi
  builder="bench-$experiment-$arm-$phase"
  docker buildx create --name "$builder" --driver docker-container
  docker buildx inspect --builder "$builder" --bootstrap
  start="$(date +%s%N)"
  docker buildx build --builder "$builder" --platform linux/amd64 --progress plain \
    --push --tag "$ref" --metadata-file "$output/$arm-$phase.metadata.json" \
    "${cache_args[@]}" "$context" 2>&1 | tee "$output/$arm-$phase.build.log"
  finish="$(date +%s%N)"
  digest="$(jq -er '.["containerimage.digest"]' "$output/$arm-$phase.metadata.json")"
  docker buildx imagetools inspect --raw "$repository@$digest" > "$output/$arm-$phase.index.json"
  manifest_digest="$(jq -r '.manifests[]? | select(.platform.os == "linux" and .platform.architecture == "amd64") | .digest' "$output/$arm-$phase.index.json")"
  if [[ -n "$manifest_digest" ]]; then
    docker buildx imagetools inspect --raw "$repository@$manifest_digest" > "$output/$arm-$phase.manifest.json"
  else
    cp "$output/$arm-$phase.index.json" "$output/$arm-$phase.manifest.json"
  fi
  jq -cn --arg arm "$arm" --arg phase "$phase" --arg image "$repository@$digest" \
    --argjson start "$start" --argjson finish "$finish" \
    --slurpfile manifest "$output/$arm-$phase.manifest.json" \
    '{arm:$arm,phase:$phase,image:$image,buildAndExportSeconds:(($finish-$start)/1000000000),
      compressedImageBytes:([$manifest[0].layers[].size]|add)}' | tee -a "$output/builds.jsonl"
  docker buildx rm "$builder"
  builder=""
}

# A new daemon per build removes implicit local caches. The baseline is the
# old production configuration, not the old PR workflow's unrelated GHA cache.
build before seed
build before update
build after seed
build after update

jq -n --slurpfile before_seed "$output/before-seed.manifest.json" \
  --slurpfile before_update "$output/before-update.manifest.json" \
  --slurpfile after_seed "$output/after-seed.manifest.json" \
  --slurpfile after_update "$output/after-update.manifest.json" '
  def delta($seed; $update):
    [$seed.layers[].digest] as $held |
    [$update.layers[] | select(.digest as $digest | $held | index($digest) | not)] as $added |
    {addedLayers:($added|length),reusedLayers:(($update.layers|length)-($added|length)),
      addedCompressedBytes:([$added[].size]|add // 0)};
  {before:delta($before_seed[0];$before_update[0]),after:delta($after_seed[0];$after_update[0])}
' > "$output/layer-deltas.json"
cat "$output/layer-deltas.json"

docker pull public.ecr.aws/docker/library/docker:28-dind@sha256:2a232a42256f70d78e3cc5d2b5d6b3276710a0de0596c145f627ecfae90282ac
for sample in 1 2 3; do
  arms=(before after)
  if [[ "$sample" == 2 ]]; then arms=(after before); fi
  for arm in "${arms[@]}"; do
    daemon="bench-$experiment-$arm-pull-$sample"
    volume="$daemon"
    docker volume create "$volume" >/dev/null
    docker run -d --privileged --name "$daemon" -e DOCKER_TLS_CERTDIR= \
      -v "$volume:/var/lib/docker" \
      public.ecr.aws/docker/library/docker:28-dind@sha256:2a232a42256f70d78e3cc5d2b5d6b3276710a0de0596c145f627ecfae90282ac \
      --storage-driver=overlay2 >/dev/null
    ready=false
    for _ in {1..60}; do
      if docker exec "$daemon" docker info >/dev/null 2>&1; then ready=true; break; fi
      sleep 1
    done
    [[ "$ready" == true ]] || { docker logs "$daemon"; exit 1; }
    [[ "$(docker exec "$daemon" docker image ls -q | wc -l)" -eq 0 ]]
    for phase in seed update; do
      ref="$(jq -sr --arg arm "$arm" --arg phase "$phase" '.[]|select(.arm==$arm and .phase==$phase)|.image' "$output/builds.jsonl")"
      start="$(date +%s%N)"
      docker exec "$daemon" docker pull "$ref" 2>&1 | tee "$output/$arm-$sample-$phase.pull.log"
      finish="$(date +%s%N)"
      docker exec "$daemon" docker image inspect "$ref" > "$output/$arm-$sample-$phase.inspect.json"
      jq -cn --arg arm "$arm" --arg phase "$phase" --argjson sample "$sample" \
        --argjson start "$start" --argjson finish "$finish" \
        '{arm:$arm,phase:$phase,sample:$sample,pullAndUnpackSeconds:(($finish-$start)/1000000000)}' | tee -a "$output/pulls.jsonl"
    done
    docker rm -f "$daemon" >/dev/null
    daemon=""
    docker volume rm "$volume" >/dev/null
    volume=""
  done
done

jq -n --slurpfile builds "$output/builds.jsonl" --slurpfile pulls "$output/pulls.jsonl" \
  --slurpfile deltas "$output/layer-deltas.json" \
  '{builds:$builds,pulls:$pulls,layerDeltas:$deltas[0]}' > "$output/results.json"
# Keep all evidence even when the success criterion fails.
jq -e '.after.addedCompressedBytes > 0 and .after.addedCompressedBytes <= 10485760' "$output/layer-deltas.json"
