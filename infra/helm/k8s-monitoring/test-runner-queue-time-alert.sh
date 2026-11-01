#!/usr/bin/env bash
# Test the runner queue-time p90 rule's expressions with Prometheus's rule engine.
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
source="${directory}/runner-queue-time-alert-rules.json"

jq -e 'length == 1 and all(.[];
  .condition == "D" and .for == "30m" and .labels.severity == "warning" and
  .noDataState == "OK" and .execErrState == "Error" and
  (.data[] | select(.refId == "C") | .model.expression) == "1 - $A / $B" and
  (.data[] | select(.refId == "D") | .model.expression) == "$B - $A > 0.1 * $B && $B >= 20")' "${source}" >/dev/null

# Grafana's math expressions match series on their labels like PromQL's
# binary operators, so D translates to one PromQL condition.
jq '.[0] as $rule | ($rule.data | map({(.refId): .model.expr}) | add) as $q |
  {groups: [{name: "Runners", interval: "1m", rules: [{
    alert: $rule.uid,
    expr: "((\($q.B)) - (\($q.A))) > 0.1 * (\($q.B)) and (\($q.B)) >= 20",
    for: $rule.for, labels: $rule.labels
  }]}]}' "${source}" > "${temporary}/rules.json"

# Each case feeds per-minute increments for one platform: jobs that were not
# held, how many of those took at most 10 s, and slow jobs held by a limit.
jq -n --arg rules "${temporary}/rules.json" --arg uid "$(jq -r '.[0].uid' "${source}")" '
  [
    ["slow", "linux", 10, 8, 0, true],
    ["on_target", "macos", 10, 10, 0, false],
    ["at_target", "linux", 10, 9, 0, false],
    ["too_few_jobs", "macos", 0.25, 0.125, 0, false],
    ["held_jobs_left_out", "linux", 10, 10, 10, false],
    ["only_held_jobs", "linux", 0, 0, 10, false]
  ] | map(
    . as [$name, $platform, $jobs, $fast, $held, $firing] |
    "tuist_runners_job_executor_queue_time_milliseconds" as $metric |
    "env=\"production\",fleet=\"pool\",platform=\"\($platform)\"" as $labels |
    {
      name: $name, interval: "1m", input_series: [
        {series: "\($metric)_count{\($labels),limit_held=\"false\"}", values: "0+\($jobs)x120"},
        {series: "\($metric)_bucket{\($labels),limit_held=\"false\",le=\"10000.0\"}", values: "0+\($fast)x120"},
        {series: "\($metric)_count{\($labels),limit_held=\"true\"}", values: "0+\($held)x120"},
        {series: "\($metric)_bucket{\($labels),limit_held=\"true\",le=\"10000.0\"}", values: "0+0x120"}
      ],
      alert_rule_test: [
        {eval_time: "20m", alertname: $uid, exp_alerts: []},
        {eval_time: "45m", alertname: $uid, exp_alerts:
          (if $firing then [{exp_labels: {platform: $platform, severity: "warning"}}] else [] end)}
      ]
    }
  ) | {rule_files: [$rules], evaluation_interval: "1m", tests: .}
' > "${temporary}/tests.json"
promtool check rules "${temporary}/rules.json"
promtool test rules "${temporary}/tests.json"
