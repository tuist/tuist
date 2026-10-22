#!/usr/bin/env bash
# Runs the Runners Acceptance workflow against one environment and waits for
# it. It runs as its own workflow run so the dispatch watchdog can cancel a job
# no runner picks up without cancelling the caller. Re-reports the probe's
# failures, whose titles name the broken layer, as this job's own.
#
# Env: GH_TOKEN, GITHUB_REPOSITORY, ENVIRONMENT, and optionally REF and
# GATE_MINUTES.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ref="${REF:-main}"
correlation="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-${ENVIRONMENT}-$(date +%s)"
gh workflow run runners-acceptance.yml --repo "${GITHUB_REPOSITORY}" --ref "${ref}" \
  -f environment="${ENVIRONMENT}" -f correlation_id="${correlation}"

run_id=""
for _ in $(seq 1 36); do
  run_id="$(gh run list --repo "${GITHUB_REPOSITORY}" --workflow runners-acceptance.yml --event workflow_dispatch \
    --limit 30 --json databaseId,displayTitle \
    --jq "[.[] | select(.displayTitle | contains(\"${correlation}\"))][0].databaseId // empty")"
  [ -n "${run_id}" ] && break
  sleep 5
done
[ -n "${run_id}" ] || fail "Runners acceptance" "the dispatched Runners Acceptance run (${correlation}) never appeared"
url="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${run_id}"
echo "Runners acceptance against ${ENVIRONMENT}: ${url}"

deadline=$(($(date +%s) + ${GATE_MINUTES:-35} * 60))
while :; do
  status="$(gh run view "${run_id}" --repo "${GITHUB_REPOSITORY}" --json status --jq .status)"
  [ "${status}" = completed ] && break
  if [ "$(date +%s)" -ge "${deadline}" ]; then
    gh run cancel "${run_id}" --repo "${GITHUB_REPOSITORY}" || true
    fail "Runners acceptance" "the probe run did not finish within ${GATE_MINUTES:-35} minutes: ${url}"
  fi
  sleep 20
done

conclusion="$(gh run view "${run_id}" --repo "${GITHUB_REPOSITORY}" --json conclusion --jq .conclusion)"
{
  echo "### Runners acceptance against ${ENVIRONMENT}: ${conclusion}"
  echo
  echo "[Probe run](${url})"
  echo
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

jobs="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${run_id}/jobs?per_page=100")"
jq -r '.jobs[] | "- \(.name): \(.conclusion // .status)"' <<< "${jobs}" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

# Re-raises every layer's failure, cache volumes included, as an error. A cache
# volume GitHub had not yet reported the job for leaves the run successful with
# a `Cache volumes inconclusive` warning, re-raised here as a warning: a GitHub
# webhook delay must not block a deploy.
jq -r '.jobs[] | select(.conclusion != "skipped") | "\(.id)\t\(.name)"' <<< "${jobs}" |
  while IFS=$'\t' read -r job_id name; do
    gh api "repos/${GITHUB_REPOSITORY}/check-runs/${job_id}/annotations" \
      --jq '.[] | select((.title // "") != "" and (.annotation_level == "failure" or .title == "Cache volumes inconclusive")) | "\(.annotation_level)\t\(.title)\t\(.message)"' |
      while IFS=$'\t' read -r annotation_level title message; do
        level=error
        [ "${annotation_level}" = failure ] || level=warning
        echo "::${level} title=${title} (${ENVIRONMENT})::${name}: ${message}"
        printf -- '- %s **%s** on %s: %s\n' "${level}" "${title}" "${name}" "${message}" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
      done
  done

[ "${conclusion}" = success ] && exit 0
fail "Runners acceptance" "the runners or their cache are broken on ${ENVIRONMENT} (${conclusion}): ${url}"
