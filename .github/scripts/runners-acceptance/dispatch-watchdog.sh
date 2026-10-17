#!/usr/bin/env bash
# Fails the run when a probe job waits longer than its bound for a runner.
# GitHub keeps a job nobody picks up queued for a day and timeout-minutes does
# not count that wait, so without this a broken dispatch path would hang the
# run instead of failing it. A stuck job cannot be cancelled on its own, so the
# watchdog cancels the run after reporting.
#
# Env: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT,
# MACOS_PICKUP_MINUTES, LINUX_PICKUP_MINUTES.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

started=$(date +%s)
while :; do
  jobs="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}/jobs?per_page=100")"
  report="$(jq -r --argjson macos "${MACOS_PICKUP_MINUTES}" --argjson linux "${LINUX_PICKUP_MINUTES}" '
    now as $now
    | [.jobs[] | select(.name | test("^(macOS|Linux) "))
       | (if (.name | startswith("macOS")) then $macos else $linux end) as $bound
       | {name, label: (.labels | join(",")),
          waiting: (.status | IN("queued", "waiting", "pending")),
          waited: ((if .started_at and (.status | IN("queued", "waiting", "pending") | not) then (.started_at | fromdateiso8601) else $now end) - (.created_at | fromdateiso8601)),
          bound: ($bound * 60)}]
    | {count: length,
       stuck: [.[] | select(.waiting and .waited > .bound)],
       waiting: [.[] | select(.waiting)],
       started: [.[] | select(.waiting | not)]}' <<< "${jobs}")"

  if [ "$(jq '.stuck | length' <<< "${report}")" -gt 0 ]; then
    jq -r '.stuck[] | "\(.name)\t\(.label)\t\(.waited | floor)"' <<< "${report}" | while IFS=$'\t' read -r name label waited; do
      echo "::error title=Dispatch::${name}: no runner picked up runs-on ${label} within $((waited / 60)) minutes"
      if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        printf '### Dispatch failed\n\n%s: no runner picked up `runs-on: %s` within %s minutes.\n\n' "${name}" "${label}" "$((waited / 60))" >> "${GITHUB_STEP_SUMMARY}"
      fi
    done
    gh run cancel "${GITHUB_RUN_ID}" --repo "${GITHUB_REPOSITORY}" || true
    exit 1
  fi

  count="$(jq '.count' <<< "${report}")"
  if [ "${count}" -gt 0 ] && [ "$(jq '.waiting | length' <<< "${report}")" -eq 0 ]; then
    jq -r '.started[] | "\(.name): picked up after \(.waited | floor)s"' <<< "${report}" | while read -r line; do pass "${line}"; done
    exit 0
  fi
  if [ "${count}" -eq 0 ] && [ $(($(date +%s) - started)) -gt 300 ]; then
    fail "Dispatch" "no probe job was created within 5 minutes"
  fi
  sleep 15
done
