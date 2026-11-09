#!/usr/bin/env bash
# Runs the Runners Acceptance workflow against one environment and waits for
# it. It runs as its own workflow run so the dispatch watchdog can cancel a job
# no runner picks up without cancelling the caller. Re-reports the probe's
# failures, whose titles name the broken layer, as this job's own.
#
# Env: GH_TOKEN, GITHUB_REPOSITORY, ENVIRONMENT, and optionally REF and
# GATE_MINUTES. Canary promotion also requires EXPECTED_LINUX_IMAGE and
# EXPECTED_MACOS_IMAGES (a JSON array of the macOS image digests it deployed).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$ENVIRONMENT" = canary ]; then
  [[ "${EXPECTED_LINUX_IMAGE:-}" =~ @sha256:[a-f0-9]{64}$ ]] ||
    fail 'Linux acceptance' 'the cascade did not supply the intended Linux image digest'
  jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and test("@sha256:[a-f0-9]{64}$"))' \
    <<< "${EXPECTED_MACOS_IMAGES:-null}" >/dev/null 2>&1 ||
    fail 'macOS acceptance' 'the cascade did not supply the intended macOS image digests'
fi

ref="${REF:-main}"
deadline=$(($(date +%s) + ${GATE_MINUTES:-35} * 60))

# Dispatches one probe run, waits for it and sets run_id, url, conclusion,
# jobs, and annotations (each failure or inconclusive annotation of its jobs as
# "level<TAB>title<TAB>job name<TAB>message").
run_probe() {
  local attempt="$1" correlation
  correlation="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-${ENVIRONMENT}-$(date +%s)-${attempt}"
  gh workflow run runners-acceptance.yml --repo "${GITHUB_REPOSITORY}" --ref "${ref}" \
    -f environment="${ENVIRONMENT}" -f correlation_id="${correlation}" \
    -f expected_linux_image="${EXPECTED_LINUX_IMAGE:-}" \
    -f expected_macos_images="${EXPECTED_MACOS_IMAGES:-}"

  run_id=""
  for _ in $(seq 1 36); do
    run_id="$(gh_retry gh run list --repo "${GITHUB_REPOSITORY}" --workflow runners-acceptance.yml --event workflow_dispatch \
      --limit 30 --json databaseId,displayTitle \
      --jq "[.[] | select(.displayTitle | contains(\"${correlation}\"))][0].databaseId // empty")"
    [ -n "${run_id}" ] && break
    sleep 5
  done
  [ -n "${run_id}" ] || fail "Runners acceptance" "the dispatched Runners Acceptance run (${correlation}) never appeared"
  url="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${run_id}"
  echo "Runners acceptance against ${ENVIRONMENT}: ${url}"

  while :; do
    status="$(gh_retry gh run view "${run_id}" --repo "${GITHUB_REPOSITORY}" --json status --jq .status)"
    [ "${status}" = completed ] && break
    if [ "$(date +%s)" -ge "${deadline}" ]; then
      gh run cancel "${run_id}" --repo "${GITHUB_REPOSITORY}" || true
      fail "Runners acceptance" "the probe run did not finish within ${GATE_MINUTES:-35} minutes: ${url}"
    fi
    sleep 20
  done

  conclusion="$(gh_retry gh run view "${run_id}" --repo "${GITHUB_REPOSITORY}" --json conclusion --jq .conclusion)"
  {
    echo "### Runners acceptance against ${ENVIRONMENT}: ${conclusion}"
    echo
    echo "[Probe run](${url})"
    echo
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

  jobs="$(gh_retry gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}/jobs?per_page=100")"
  jq -r '.jobs[] | "- \(.name): \(.conclusion // .status)"' <<< "${jobs}" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

  annotations="$(jq -r '.jobs[] | select(.conclusion != "skipped") | "\(.id)\t\(.name)"' <<< "${jobs}" |
    while IFS=$'\t' read -r job_id name; do
      gh_retry gh api "repos/${GITHUB_REPOSITORY}/check-runs/${job_id}/annotations" \
        --jq '.[] | select((.title // "") != "" and (.annotation_level == "failure" or .title == "Cache volumes inconclusive")) | "\(.annotation_level)\t\(.title)\t\(.message)"' |
        while IFS=$'\t' read -r annotation_level title message; do
          printf '%s\t%s\t%s\t%s\n' "${annotation_level}" "${title}" "${name}" "${message}"
        done
    done)"
}

# Re-raises every layer's failure, cache volumes included, as an error, or as
# a warning when the run is being retried. A cache volume GitHub had not yet
# reported the job for, or one an overlapping probe run saved over, leaves the
# run successful with a `Cache volumes inconclusive` warning, re-raised here as
# a warning: neither must block a deploy.
report_annotations() {
  local failure_level="$1"
  [ -n "${annotations}" ] || return 0
  while IFS=$'\t' read -r annotation_level title name message; do
    level="${failure_level}"
    [ "${annotation_level}" = failure ] || level=warning
    echo "::${level} title=${title} (${ENVIRONMENT})::${name}: ${message}"
    printf -- '- %s **%s** on %s: %s\n' "${level}" "${title}" "${name}" "${message}" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  done <<< "${annotations}"
}

# A probe the watchdog failed only because no runner picked it up, with no
# other job failing (the watchdog's own job can end failed or cancelled), never
# reached the runners: GitHub occasionally drops the
# workflow_job.queued webhook dispatch enqueues jobs from, and nothing replays
# it. Dispatch it once more; a second dispatch failure blocks the deploy.
dispatch_only_failure() {
  [ "${conclusion}" != success ] &&
    [ -n "${annotations}" ] &&
    [ -z "$(cut -f1,2 <<< "${annotations}" | grep -v $'^failure\tDispatch$')" ] &&
    jq -e '[.jobs[] | select(.conclusion == "failure" and .name != "Dispatch watchdog")] | length == 0' <<< "${jobs}" >/dev/null
}

run_probe 1
if dispatch_only_failure; then
  report_annotations warning
  echo "::warning title=Dispatch retried (${ENVIRONMENT})::no runner picked up a probe job in ${url}; dispatching the probe run once more"
  printf -- '- warning **Dispatch retried**: no runner picked up a probe job in %s; dispatching the probe run once more\n\n' "${url}" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  run_probe 2
fi
report_annotations error

[ "${conclusion}" = success ] || fail "Runners acceptance" "the runners or their cache are broken on ${ENVIRONMENT} (${conclusion}): ${url}"
# A successful workflow with a skipped/missing Linux probe must not promote.
probes=('Linux native ' 'Linux container ')
if [ "$ENVIRONMENT" = canary ]; then
  for phase in cold same-size-write verify-final; do
    probes+=("Linux Docker cache $phase / Build")
  done
fi
for probe in "${probes[@]}"; do
  jq -e --arg prefix "$probe" '[.jobs[] | select(.name | startswith($prefix))]
    | length > 0 and all(.[]; .conclusion == "success")' <<< "$jobs" >/dev/null ||
    fail 'Linux acceptance' "${probe}coverage was missing, skipped, or unsuccessful: ${url}"
done
