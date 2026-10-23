#!/usr/bin/env bash
# Build-only owner qualification: no registry login, publication or live cluster.
set -euo pipefail
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { echo 'Linux amd64 is required' >&2; exit 1; }
repo=$(git rev-parse --show-toplevel)
cd "$repo/kura"
: "${RUNNER_TEMP:?an isolated runner temporary directory is required}"
: "${KURA_QUALIFICATION_OUTPUT:?an isolated evidence directory is required}"
out=$KURA_QUALIFICATION_OUTPUT
[[ ! -e $out ]] || { echo 'qualification output already exists' >&2; exit 1; }
mkdir -p "$out"
source=$(git rev-parse HEAD)
base=$(git merge-base HEAD origin/main)
printf 'SOURCE=%s\nBASELINE=%s\n' "$source" "$base" | tee "$out/SOURCE"
bazel=$(mise which bazel)
node=$(mise which node)
"$bazel" version > "$out/bazel-version.txt"
"$node" --version > "$out/node-version.txt"
uname -a > "$out/platform.txt"
docker version > "$out/docker-version.txt"
df -h . "$RUNNER_TEMP" > "$out/disk-before.txt"
work=$(mktemp -d "$RUNNER_TEMP/kura-trust-source.XXXXXX")
prefix=tuist-kura-trust-${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-0}
baseline_image=$prefix-baseline
candidate_image=$prefix-candidate
cleanup() {
  docker image rm "$baseline_image" "$candidate_image" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
mkdir -p "$work/baseline"
git archive "$base" kura | tar -x -C "$work/baseline"
cache=$RUNNER_TEMP/kura-trust-bazel-cache
flags=(--jobs=4 --disk_cache="$cache/disk" --repository_cache="$cache/download" --experimental_disk_cache_gc_max_size=4G)
for tree in "$work/baseline/kura" "$repo/kura"; do
  (
    cd "$tree"
    "$bazel" build //:kura --define=kura_deny_warnings=true "${flags[@]}"
    mkdir -p bin/amd64
    cp bazel-bin/kura bin/amd64/kura
  )
done
sha256sum "$work/baseline/kura/bin/amd64/kura" "$repo/kura/bin/amd64/kura" > "$out/binary-sha256.txt"
"$bazel" test //... --define=kura_deny_warnings=true "${flags[@]}" --nocache_test_results --test_output=all
while IFS= read -r report; do
  name=${report#bazel-testlogs/}
  cp "$report" "$out/${name//\//_}"
done < <(find -L bazel-testlogs -type f -name test.xml)
"$bazel" test //:certificate_trust_test --define=kura_deny_warnings=true "${flags[@]}" --nocache_test_results --test_output=all \
  --test_arg=--ignored --test_arg=public_controls_fail_for_certificates --test_arg=valid_pkcs1_and_sec1_identities \
  --test_env=TUIST_TRUST_LIVE=1 --test_env=KURA_TRUST_OPENSSL=/usr/bin/openssl
cp bazel-testlogs/certificate_trust_test/test.xml "$out/certificate-trust-opt-ins.xml"
# Both binaries use precisely the candidate release assembly and cached base
# layers. This compares the verifier change, not two unrelated OS/package sets.
for variant in baseline candidate; do
  tree=$repo/kura
  revision=$source
  image=$candidate_image
  if [[ $variant == baseline ]]; then tree=$work/baseline/kura; revision=$base; image=$baseline_image; fi
  docker build --load --platform linux/amd64 \
    --file "$repo/kura/Dockerfile.release" \
    --build-context "certificate-trust=$repo/infra/certificate-trust" \
    --label "org.opencontainers.image.revision=$revision" \
    --iidfile "$out/$variant-image-id.txt" --tag "$image" "$tree"
  docker image inspect --format '{{.Id}} {{.Os}}/{{.Architecture}}' "$image" > "$out/$variant-platform.txt"
  docker image inspect --format '{{json .RootFS.Layers}}' "$image" > "$out/$variant-layers.json"
  docker run --rm "$image" --version > "$out/$variant-version.txt"
done
"$node" --input-type=module -e '
  import fs from "node:fs";
  import assert from "node:assert/strict";
  const layers = process.argv.slice(1).map(file => JSON.parse(fs.readFileSync(file, "utf8")));
  assert.ok(layers[0].length > 1 && layers[0].length === layers[1].length);
  assert.deepEqual(layers[0].slice(0, -1), layers[1].slice(0, -1), "runtime layers must differ only in the binary COPY");
' "$out/baseline-layers.json" "$out/candidate-layers.json"
# ABBA controls order/host variance; only these containers and networks are
# created and removed by the shared resource harness. No global Docker prune.
for run in before-1 after-1 after-2 before-2; do
  image=$candidate_image
  if [[ $run == before-* ]]; then image=$baseline_image; fi
  KURA_RESOURCE_OUTPUT="$out/$run" "$node" test/e2e/provider-topology/resources.mjs "$run" "$image"
  "$node" test/e2e/provider-topology/summarize.mjs "$out/$run"
done
"$node" test/e2e/provider-topology/compare.mjs "$out/before-1" "$out/after-1" "$out/after-2" "$out/before-2" > "$out/comparison.json"
# Retain hashes/IDs only: runnable binaries/images are not published as artifacts.
df -h . "$RUNNER_TEMP" > "$out/disk-after.txt"
