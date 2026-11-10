#!/usr/bin/env bash
# Test the shipped Grafana expressions with Prometheus's actual rule engine.
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
source="${directory}/runner-macos-host-alert-rules.json"

jq -e 'all(.[];
  .condition == "C" and .labels.severity == "warning" and
  .noDataState == "OK" and .execErrState == "Error" and
  (.data[] | select(.refId == "C") | .model |
    .expression == "A" and .type == "threshold" and
    .conditions[0].evaluator == {params: [0], type: "gt"}))' "${source}" >/dev/null
jq '{groups: [{name: "Runner host health", interval: "1m", rules: map({
  alert: .uid, expr: ("(" + (.data[] | select(.refId == "A") | .model.expr) + ") > 0"),
  for: .for, labels: .labels
})}]}' "${source}" > "${temporary}/rules.json"

jq --arg rules "${temporary}/rules.json" '
  . as $ruleset |
  [
    ["old_kernel", "26.3.2", "25.3.0", 8812800, 12714, 1, "0+60x22", [0,1]],
    ["before_40_days", "26.3.2", "25.3.0", 3369600, 100, 1, "0+60x22", []],
    ["at_40_days", "26.3.2", "25.3.0", 3456000, 100, 1, "0+60x22", []],
    ["fixed_peer", "26.6.2", "25.6.0", 5270400, 1, 1, "0+60x22", []],
    ["outside_tahoe", "15.7", "24.6.0", 8812800, 100, 1, "0+60x22", []],
    ["future_kernel", "27.0", "26.0.0", 8812800, 100, 1, "0+60x22", []],
    ["fixed_but_socket_pressure", "26.6.2", "25.6.0", 5270400, 6000, 1, "0+60x22", [1]],
    ["at_socket_threshold", "26.6.2", "25.6.0", 5270400, 5000, 1, "0+60x22", []],
    ["stopped_collector", "26.3.2", "25.3.0", 8812800, 12714, 1, "0+0x22", [2]],
    ["command_failed", "26.6.2", "25.6.0", 5270400, 100, 0, "0+60x22", [2]]
  ] | map(
    . as [$name,$product,$kernel,$uptime,$sockets,$success,$mtime,$firing] |
    {instance: $name, job: "tuist-macos-node-exporter", cluster: "tuist-production", env: "production"} as $labels |
    ($labels | to_entries | map("\(.key)=\(.value|tojson)") | join(",")) as $encoded |
    {
      name: $name, interval: "1m", input_series: [
        {series: "macos_host_info{\($encoded),product_version=\($product|tojson),kernel_release=\($kernel|tojson)}", values: "1+0x22"},
        {series: "macos_host_uptime_seconds{\($encoded)}", values: "\($uptime)+0x22"},
        {series: "macos_host_tcp_time_wait{\($encoded)}", values: "\($sockets)+0x22"},
        {series: "macos_host_health_collection_success{\($encoded)}", values: "\($success)+0x22"},
        {series: "node_textfile_mtime_seconds{\($encoded),file=\"/var/lib/tuist-host-sensors/host_sensors.prom\"}", values: $mtime}
      ],
      alert_rule_test: [range(0;3) as $index | ["4m", "20m"][] as $time | {
        eval_time: $time, alertname: $ruleset[$index].uid,
        exp_alerts: (if $time == "20m" and ($firing|index($index)) != null then [{
          exp_labels: ($labels + $ruleset[$index].labels +
            (if $index == 0 then {product_version: $product, kernel_release: $kernel} else {} end))
        }] else [] end)
      }]
    }
  ) | . + [{name: "missing_metrics", interval: "1m", input_series: [],
    alert_rule_test: [$ruleset[] | {eval_time: "20m", alertname: .uid, exp_alerts: []}]
  }] | {rule_files: [$rules], evaluation_interval: "1m", tests: .}
' "${source}" > "${temporary}/tests.json"
promtool check rules "${temporary}/rules.json"
promtool test rules "${temporary}/tests.json"
