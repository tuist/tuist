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

[ "${conclusion}" = success ] && exit 0

jq -r '.jobs[] | select(.conclusion != "success" and .conclusion != "skipped") | "\(.id)\t\(.name)"' <<< "${jobs}" |
  while IFS=$'\t' read -r job_id name; do
    gh api "repos/${GITHUB_REPOSITORY}/check-runs/${job_id}/annotations" \
      --jq '.[] | select(.annotation_level == "failure" and (.title // "") != "") | "\(.title)\t\(.message)"' |
      while IFS=$'\t' read -r title message; do
        echo "::error title=${title} (${ENVIRONMENT})::${name}: ${message}"
        printf -- '- **%s** on %s: %s\n' "${title}" "${name}" "${message}" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
      done
  done
fail "Runners acceptance" "the runners or their cache are broken on ${ENVIRONMENT} (${conclusion}): ${url}"
