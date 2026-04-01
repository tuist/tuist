#!/usr/bin/env bash
set -euo pipefail

: "${PR_SHA:?PR_SHA must be set}"
: "${MAIN_SHA:?MAIN_SHA must be set}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID must be set}"
: "${GITHUB_SERVER_URL:?GITHUB_SERVER_URL must be set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

P50_ABS_FAST_MAX="20"
P50_ABS_FAST_THRESHOLD="5"
P50_ABS_MEDIUM_MAX="100"
P50_ABS_MEDIUM_THRESHOLD="15"
P50_RELATIVE_MEDIUM_THRESHOLD="1.35"
P50_RELATIVE_SLOW_THRESHOLD="1.20"
THROUGHPUT_THRESHOLD="0.90"
ERROR_RATE_THRESHOLD="0"
VERDICT="pass"
REGRESSIONS=""
SUMMARY=""

add_failure() {
  local region="$1" metric="$2" check_name="$3" baseline="$4" pr="$5" delta="$6"
  REGRESSIONS="${REGRESSIONS}| ${region} | ${metric} | ${check_name} | ${baseline} | ${pr} | ${delta} | ❌ |
"
  VERDICT="fail"
}

compare_metric() {
  local region="$1" pr_file="$2" baseline_file="$3" metric="$4"

  local pr_p50 pr_p95 pr_p99 pr_throughput pr_error_rate pr_iters pr_min_iters
  local base_p50 base_throughput base_iters

  pr_p50=$(jq -r ".metrics[\"$metric\"].p50 // 0" "$pr_file")
  pr_p95=$(jq -r ".metrics[\"$metric\"].p95 // 0" "$pr_file")
  pr_p99=$(jq -r ".metrics[\"$metric\"].p99 // 0" "$pr_file")
  pr_throughput=$(jq -r ".metrics[\"$metric\"].throughput // 0" "$pr_file")
  pr_error_rate=$(jq -r ".metrics[\"$metric\"].error_rate // 0" "$pr_file")
  pr_iters=$(jq -r ".metrics[\"$metric\"].iterations // 0" "$pr_file")
  pr_min_iters=$(jq -r ".metrics[\"$metric\"].min_iterations // 0" "$pr_file")

  base_p50=$(jq -r ".metrics[\"$metric\"].p50 // 0" "$baseline_file")
  base_throughput=$(jq -r ".metrics[\"$metric\"].throughput // 0" "$baseline_file")
  base_iters=$(jq -r ".metrics[\"$metric\"].iterations // 0" "$baseline_file")

  if [ "$(echo "$pr_error_rate > $ERROR_RATE_THRESHOLD" | bc -l)" -eq 1 ]; then
    local pct
    pct=$(printf "%.2f" "$(echo "$pr_error_rate * 100" | bc -l)")
    add_failure "$region" "$metric" "error_rate" "0%" "${pct}%" "-"
  fi

  local iterations_valid=1
  if [ "$(echo "$pr_min_iters > 0" | bc -l)" -eq 1 ]; then
    if [ "$(echo "$base_iters < $pr_min_iters" | bc -l)" -eq 1 ]; then
      iterations_valid=0
      add_failure "$region" "$metric" "baseline_iterations" "$(printf '%.0f' "$base_iters")" ">= $(printf '%.0f' "$pr_min_iters")" "-"
    fi

    if [ "$(echo "$pr_iters < $pr_min_iters" | bc -l)" -eq 1 ]; then
      iterations_valid=0
      add_failure "$region" "$metric" "pr_iterations" ">= $(printf '%.0f' "$pr_min_iters")" "$(printf '%.0f' "$pr_iters")" "-"
    fi
  fi

  if [ "$iterations_valid" -eq 1 ] && [ "$(echo "$base_p50 > 0" | bc -l)" -eq 1 ]; then
    local p50_diff
    local p50_regression=0
    p50_diff=$(echo "$pr_p50 - $base_p50" | bc -l)

    if [ "$(echo "$base_p50 < $P50_ABS_FAST_MAX" | bc -l)" -eq 1 ]; then
      if [ "$(echo "$p50_diff > $P50_ABS_FAST_THRESHOLD" | bc -l)" -eq 1 ]; then
        p50_regression=1
      fi
    elif [ "$(echo "$base_p50 < $P50_ABS_MEDIUM_MAX" | bc -l)" -eq 1 ]; then
      if [ "$(echo "$p50_diff > $P50_ABS_MEDIUM_THRESHOLD" | bc -l)" -eq 1 ]; then
        p50_regression=1
      fi
    elif [ "$(echo "$base_p50 < 1000" | bc -l)" -eq 1 ]; then
      if [ "$(echo "$pr_p50 > $base_p50 * $P50_RELATIVE_MEDIUM_THRESHOLD" | bc -l)" -eq 1 ]; then
        p50_regression=1
      fi
    else
      if [ "$(echo "$pr_p50 > $base_p50 * $P50_RELATIVE_SLOW_THRESHOLD" | bc -l)" -eq 1 ]; then
        p50_regression=1
      fi
    fi

    if [ "$p50_regression" -eq 1 ]; then
      local delta
      delta=$(printf "%.1f" "$(echo "($pr_p50 / $base_p50 - 1) * 100" | bc -l)")
      add_failure "$region" "$metric" "p50" "$(printf '%.2f' "$base_p50")ms" "$(printf '%.2f' "$pr_p50")ms" "+${delta}%"
    fi
  fi

  if [ "$iterations_valid" -eq 1 ] && [ "$(echo "$base_throughput > 0" | bc -l)" -eq 1 ]; then
    if [ "$(echo "$pr_throughput < $base_throughput * $THROUGHPUT_THRESHOLD" | bc -l)" -eq 1 ]; then
      local delta
      delta=$(printf "%.1f" "$(echo "(1 - $pr_throughput / $base_throughput) * 100" | bc -l)")
      add_failure "$region" "$metric" "throughput" "$(printf '%.1f' "$base_throughput")/s" "$(printf '%.1f' "$pr_throughput")/s" "-${delta}%"
    fi
  fi

  SUMMARY="${SUMMARY}| ${region} | ${metric} | $(printf '%.0f' "$base_iters") | $(printf '%.0f' "$pr_iters") | $(printf '%.0f' "$pr_min_iters") | $(printf '%.2f' "$pr_p50") | $(printf '%.2f' "$pr_p95") | $(printf '%.2f' "$pr_p99") | $(printf '%.1f' "$pr_throughput") | $(printf '%.2f' "$(echo "$pr_error_rate * 100" | bc -l)")% |
"
}

WORKFLOW_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

for region in eu-central; do
  PR_FILE="k6-result-${region}/result.json"
  BASELINE_FILE="baseline-result-${region}/result.json"

  if [ ! -f "$BASELINE_FILE" ]; then
    add_failure "$region" "workflow" "baseline" "present" "missing" "-"
    continue
  fi

  if [ ! -f "$PR_FILE" ]; then
    add_failure "$region" "workflow" "pr_result" "present" "missing" "-"
    continue
  fi

  METRICS=$(jq -r '.metrics | keys[]' "$PR_FILE")
  for metric in $METRICS; do
    compare_metric "$region" "$PR_FILE" "$BASELINE_FILE" "$metric"
  done

  BASELINE_ONLY=$(jq -r --argjson pr "$(jq '.metrics | keys' "$PR_FILE")" '.metrics | keys[] | select(. as $k | $pr | index($k) | not)' "$BASELINE_FILE")
  for metric in $BASELINE_ONLY; do
    add_failure "$region" "$metric" "missing_in_pr" "present" "missing" "-"
  done
done

REPORT="<!-- cache-load-test -->
## Cache Load Test
"

if [ "$VERDICT" = "fail" ]; then
  REPORT="${REPORT}
**Status:** ❌ Regression detected"
else
  REPORT="${REPORT}
**Status:** ✅ Passed"
fi

REPORT="${REPORT}
**PR SHA:** \`${PR_SHA}\`
**Baseline:** \`main\` @ \`${MAIN_SHA}\`
**Workflow:** [${GITHUB_RUN_ID}](${WORKFLOW_URL})
"

if [ -n "$REGRESSIONS" ]; then
  REPORT="${REPORT}
### Regressions
| Region | Metric | Check | Baseline | PR | Delta | Status |
|---|---|---|---:|---:|---:|---|
${REGRESSIONS}"
fi

if [ -n "$SUMMARY" ]; then
  REPORT="${REPORT}
### Summary
| Region | Metric | Baseline Iters | PR Iters | Min Iters | p50 (ms) | p95 (ms) | p99 (ms) | Throughput | Error Rate |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
${SUMMARY}"
fi

echo "verdict=$VERDICT" >> "$GITHUB_OUTPUT"
echo "$REPORT" > report.md
