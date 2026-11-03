#!/usr/bin/env bash
set -euo pipefail

: "${CACHE_EXPERIMENT:?Use the same experiment key across all phases}"
: "${CACHE_PHASE:?cold, warm-layers, changed-source, or same-size-write}"
: "${CACHE_DRIVER:?docker or docker-container}"
[[ "$CACHE_DRIVER" == docker || "$CACHE_DRIVER" == docker-container ]]
case "$CACHE_PHASE" in
  cold|warm-layers) version=first; previous= ;;
  changed-source) version=second; previous=first ;;
  same-size-write) version=third!; previous=second ;;
  verify-final) version=third!; previous= ;;
  *) echo 'Invalid phase' >&2; exit 1 ;;
esac

# The data-root cache is best-effort. Do not misreport a fallback as a warm run.
jq -e '.mounted == true' /home/runner/.tuist-docker.json >/dev/null
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
results="${RUNNER_TEMP:?}/docker-build-cache-results"
mkdir -p "$results"
experiment=$(printf '%s' "$CACHE_EXPERIMENT" | sha256sum | cut -d' ' -f1)
cat > "$work/Dockerfile" <<'DOCKERFILE'
FROM golang:1.26.5-alpine AS build
ARG EXPERIMENT
WORKDIR /src
RUN printf '%s' "$EXPERIMENT" > /experiment
COPY main.go .
RUN --mount=type=cache,id=tuist-proof-${EXPERIMENT},target=/root/.cache/go-build \
    if [ -f /root/.cache/go-build/proof ]; then echo MOUNT_REUSED; else echo MOUNT_COLD; fi; \
    cat /root/.cache/go-build/proof 2>/dev/null || true; \
    CGO_ENABLED=0 go build -o /app main.go && cp main.go /root/.cache/go-build/proof
FROM scratch
COPY --from=build /app /app
DOCKERFILE
printf 'package main\nimport ("fmt"; _ "net/http")\nfunc main() { fmt.Println("%s") }\n' "$version" > "$work/main.go"

docker version > "$results/docker-version.txt"
docker buildx inspect "${CACHE_BUILDER:-default}" > "$results/builder.txt"
start=$(date +%s%N)
docker buildx build --builder "${CACHE_BUILDER:-default}" --progress=plain \
  --build-arg "EXPERIMENT=$experiment" --output "type=local,dest=$work/output" \
  "$work" 2>&1 | tee "$results/build.log"
elapsed_ms=$(( ($(date +%s%N) - start) / 1000000 ))
test "$("$work/output/app")" = "$version"
case "$CACHE_PHASE" in
  cold) grep -Eq '^#[0-9]+ [0-9.]+ MOUNT_COLD$' "$results/build.log" ;;
  warm-layers|verify-final)
    # Require the compile vertex itself to hit, not an unrelated FROM/COPY.
    awk '/^#[0-9]+ .*RUN --mount=type=cache/ { vertex=$1 }
      $1 == vertex && $2 == "CACHED" { hit=1 }
      END { exit !hit }' "$results/build.log"
    ;;
  *)
    grep -Eq '^#[0-9]+ [0-9.]+ MOUNT_REUSED$' "$results/build.log"
    grep -F "fmt.Println(\"$previous\")" "$results/build.log"
    ;;
esac
jq -n --arg phase "$CACHE_PHASE" --arg driver "$CACHE_DRIVER" \
  --arg experiment "$CACHE_EXPERIMENT" --arg source "$GITHUB_SHA" \
  --arg run "$GITHUB_RUN_ID" --arg arch "$(uname -m)" --argjson elapsed_ms "$elapsed_ms" \
  '{phase:$phase, driver:$driver, experiment:$experiment, source:$source, run:$run, arch:$arch,
    build_ms:$elapsed_ms, assertions_passed:true}' > "$results/result.json"
{
  echo '| Driver | Phase | Build duration | Cache assertions |'
  echo '| --- | --- | ---: | --- |'
  echo "| $CACHE_DRIVER | $CACHE_PHASE | ${elapsed_ms} ms | Passed |"
  echo
  echo 'Timing includes the Docker build and local output export, excluding builder setup, queueing and post-job publication.'
  echo 'Run cold → warm-layers → changed-source → same-size-write with the same experiment key, revision and profile. Wait for each saved cache to publish before the next job.'
} >> "$GITHUB_STEP_SUMMARY"
