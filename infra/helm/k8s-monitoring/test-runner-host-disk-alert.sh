#!/usr/bin/env bash
# Exercise the shipped capacity query, not a second copy of its selector.
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
source="${directory}/runner-host-disk-alert-rule.json"

jq -e '.noDataState == "NoData" and .execErrState == "Error" and
  .for == "15m" and .condition == "C" and .isPaused == false and
  (.data[] | select(.refId == "C") | .model |
    .expression == "A" and .type == "threshold" and
    .conditions[0].evaluator == {params: [10], type: "lt"})' "${source}" >/dev/null
jq '{groups: [{name: "Runner disk", interval: "1m", rules: [{
  alert: .uid, expr: ("(" + (.data[] | select(.refId == "A") | .model.expr) + ") < 10"),
  for: .for
}]}]}' "${source}" > "${temporary}/rules.json"

jq --arg rules "${temporary}/rules.json" '
  .uid as $uid | (.data[] | select(.refId == "A") | .model.expr) as $expr |
  [
    ["rented_low", "tuist-tuist-runners-fleet-abc", "production", "/", 9, true],
    ["rack_low", "tuist-tuist-rack-fleet-ber1-runner-b03", "production", "/", 8, true],
    ["lent_canary_low", "tuist-canary-rack-fleet-ber1-runner-b02", "canary", "/", 7, true],
    ["lent_staging_low", "tuist-staging-rack-fleet-ber1-runner-b01", "staging", "/", 6, true],
    ["boundary", "tuist-tuist-rack-fleet-ber1-runner-b04", "production", "/", 10, true],
    ["healthy", "tuist-tuist-rack-fleet-ber1-runner-b05", "production", "/", 41, true],
    ["builder_excluded", "tuist-tuist-builders-fleet-abc", "production", "/", 1, false],
    ["processor_excluded", "tuist-tuist-macos-fleet-abc", "production", "/", 1, false],
    ["other_mount_excluded", "tuist-tuist-rack-fleet-ber1-runner-b06", "production", "/Volumes/cache", 1, false],
    ["missing_size", "tuist-tuist-rack-fleet-ber1-runner-b07", "production", "/", 1, false],
    ["missing_avail", "tuist-tuist-rack-fleet-ber1-runner-b08", "production", "/", 1, false]
  ] | map(
    . as [$name,$instance,$env,$mount,$avail,$included] |
    {cluster: ("tuist-" + $env), env: $env, instance: $instance} as $labels |
    ($labels + {job: "tuist-macos-node-exporter", mountpoint: $mount, device: "/dev/disk3s1", fstype: "apfs"} |
      to_entries | map("\(.key)=\(.value|tojson)") | join(",")) as $encoded |
    {
      name: $name, interval: "1m", input_series: [
        (if $name != "missing_avail" then {series: "node_filesystem_avail_bytes{\($encoded)}", values: "\($avail)+0x20"} else empty end),
        (if $name != "missing_size" then {series: "node_filesystem_size_bytes{\($encoded)}", values: "100+0x20"} else empty end)
      ],
      promql_expr_test: [{expr: $expr, eval_time: "20m", exp_samples:
        (if $included then [{labels: ("{" + ($labels | to_entries | map("\(.key)=\(.value|tojson)") | join(",")) + "}"), value: $avail}] else [] end)}],
      alert_rule_test: [["14m", "15m"][] as $time | {
        eval_time: $time, alertname: $uid,
        exp_alerts: (if $time == "15m" and $included and $avail < 10 then [{exp_labels: $labels}] else [] end)
      }]
    }
  ) | . + [{name: "all_metrics_missing", interval: "1m", input_series: [],
    promql_expr_test: [{expr: $expr, eval_time: "20m", exp_samples: []}],
    alert_rule_test: [{eval_time: "20m", alertname: $uid, exp_alerts: []}]
  }] | {rule_files: [$rules], evaluation_interval: "1m", tests: .}
' "${source}" > "${temporary}/tests.json"
promtool check rules "${temporary}/rules.json"
promtool test rules "${temporary}/tests.json"
