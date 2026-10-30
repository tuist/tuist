#!/usr/bin/env bash
# Drives the shard API the way a sharded build job does: create a plan, then
# immediately upload its artifacts in parallel (start, sign, PUT, complete),
# then fetch every shard. Requests go out as soon as the plan exists and spread
# over the server's pods and ClickHouse connections, so a server that reads the
# just-created plan back from a replica that has not fetched it yet answers 404
# and the probe fails. Nothing is retried.
#
# Usage: shard-plan-visibility-probe.sh <account>/<project> [<account>/<project> ...]
#
# Environment:
#   TUIST_URL              Server to probe (default https://canary.tuist.dev).
#   TUIST_AUTH_EMAIL, TUIST_AUTH_PASSWORD
#                          Exchanged for a token when set. Otherwise the GitHub
#                          Actions OIDC token is exchanged, which reaches the
#                          projects connected to this repository.
#   TUIST_PROBE_ITERATIONS Plans per project (default 10).
#   TUIST_PROBE_ARTIFACTS  Artifacts uploaded in parallel per plan (default 6).
#   TUIST_PROBE_CREATE_BUILD_SYSTEMS
#                          Space-separated build systems, one per project, used
#                          to create a project that does not exist yet.
set -euo pipefail

server="${TUIST_URL:-https://canary.tuist.dev}"
iterations="${TUIST_PROBE_ITERATIONS:-10}"
artifact_count="${TUIST_PROBE_ARTIFACTS:-6}"
read -r -a create_build_systems <<< "${TUIST_PROBE_CREATE_BUILD_SYSTEMS:-}"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <account>/<project> [<account>/<project> ...]" >&2
  exit 64
fi

if [ -n "${TUIST_AUTH_EMAIL:-}" ]; then
  token="$(curl -fsS -X POST "$server/api/auth" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg email "$TUIST_AUTH_EMAIL" --arg password "$TUIST_AUTH_PASSWORD" '{email: $email, password: $password}')" \
    | jq -r '.access_token')"
else
  id_token="$(curl -fsS -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=tuist" | jq -r '.value')"
  token="$(curl -fsS -X POST "$server/api/auth/oidc/token" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg token "$id_token" '{token: $token}')" | jq -r '.access_token')"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Sends one request, writes the body to $1 and prints the status code.
request() {
  local body="$1" method="$2" url="$3" data="${4:-}"
  if [ -n "$data" ]; then
    curl -sS -o "$body" -w '%{http_code}' -X "$method" "$url" \
      -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d "$data" || true
  else
    curl -sS -o "$body" -w '%{http_code}' -X "$method" "$url" -H "Authorization: Bearer $token" || true
  fi
}

# Uploads one artifact of a plan. Prints "ok" on success and the failed step
# otherwise.
upload_artifact() {
  local api="$1" plan_id="$2" artifact="$3" body status upload_id part_url etag
  body="$(mktemp "$work/body.XXXXXX")"

  status="$(request "$body" POST "$api/upload/start" \
    "$(jq -n --arg id "$plan_id" --arg artifact "$artifact" '{shard_plan_id: $id, artifact: $artifact}')")"
  [ "$status" = 200 ] || { echo "$artifact upload/start: HTTP $status $(head -c 200 "$body")"; return; }
  upload_id="$(jq -r '.data.upload_id' "$body")"

  status="$(request "$body" POST "$api/upload/generate-url" \
    "$(jq -n --arg id "$plan_id" --arg upload "$upload_id" --arg artifact "$artifact" \
      '{shard_plan_id: $id, upload_id: $upload, part_number: 1, artifact: $artifact}')")"
  [ "$status" = 200 ] || { echo "$artifact upload/generate-url: HTTP $status $(head -c 200 "$body")"; return; }
  part_url="$(jq -r '.data.url' "$body")"

  etag="$(curl -sS -X PUT --data-binary "shard plan visibility probe" -D - -o /dev/null "$part_url" \
    | tr -d '\r' | awk 'tolower($1) == "etag:" { print $2 }')" || etag=""
  [ -n "$etag" ] || { echo "$artifact part upload: no ETag"; return; }

  status="$(request "$body" POST "$api/upload/complete" \
    "$(jq -n --arg id "$plan_id" --arg upload "$upload_id" --arg etag "$etag" --arg artifact "$artifact" \
      '{shard_plan_id: $id, upload_id: $upload, parts: [{part_number: 1, etag: $etag}], artifact: $artifact}')")"
  [ "$status" = 200 ] || { echo "$artifact upload/complete: HTTP $status $(head -c 200 "$body")"; return; }
  echo ok
}

failures=0
index=0
for full_handle in "$@"; do
  api="$server/api/projects/$full_handle/tests/shards"
  build_system="${create_build_systems[$index]:-}"
  index=$((index + 1))

  if [ -n "$build_system" ] && [ "$(request "$work/project" GET "$server/api/projects/$full_handle")" = 404 ]; then
    status="$(request "$work/project" POST "$server/api/projects" \
      "$(jq -n --arg handle "$full_handle" --arg build_system "$build_system" '{full_handle: $handle, build_system: $build_system}')")"
    if [ "$status" != 200 ]; then
      echo "::error::$full_handle: creating the project returned HTTP $status $(head -c 200 "$work/project")"
      failures=$((failures + 1))
      continue
    fi
  fi

  for iteration in $(seq 1 "$iterations"); do
    reference="shard-plan-visibility-probe-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$(date +%s)-$iteration"
    step="$full_handle plan $iteration"

    status="$(request "$work/plan" POST "$api" \
      "$(jq -n --arg reference "$reference" '{reference: $reference, modules: ["ProbeA", "ProbeB"], shard_total: 2}')")"
    if [ "$status" != 200 ]; then
      echo "::error::$step: create returned HTTP $status $(head -c 200 "$work/plan")"
      failures=$((failures + 1))
      continue
    fi
    plan_id="$(jq -r '.id' "$work/plan")"
    shard_count="$(jq -r '.shard_count' "$work/plan")"

    artifacts=(shared)
    for module in $(seq 2 "$artifact_count"); do artifacts+=("module:Probe$module"); done
    for artifact in "${artifacts[@]}"; do
      upload_artifact "$api" "$plan_id" "$artifact" > "$work/upload.${artifact//:/-}" &
    done
    wait

    errors=""
    for artifact in "${artifacts[@]}"; do
      result="$(cat "$work/upload.${artifact//:/-}")"
      [ "$result" = ok ] || errors+=$'\n'"${result:-$artifact: the upload stopped without a result}"
    done
    rm -f "$work"/upload.*
    for shard_index in $(seq 0 $((shard_count - 1))); do
      status="$(request "$work/shard" GET "$api/$reference/$shard_index?shard_plan_id=$plan_id")"
      [ "$status" = 200 ] || errors+=$'\n'"shard $shard_index: HTTP $status $(head -c 200 "$work/shard")"
    done

    if [ -n "${errors//$'\n'/}" ]; then
      while IFS= read -r error; do
        [ -n "$error" ] && echo "::error::$step ($plan_id): $error"
      done <<< "$errors"
      failures=$((failures + 1))
    else
      echo "$step: ${#artifacts[@]} artifacts uploaded, $shard_count shards fetched"
    fi
  done
done

if [ "$failures" -gt 0 ]; then
  echo "::error::$failures shard plan(s) were not usable right after creation on $server"
  exit 1
fi
echo "Every shard plan was usable right after creation on $server."
