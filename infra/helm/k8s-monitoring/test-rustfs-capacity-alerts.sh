#!/usr/bin/env bash
# Exercise the shipped RustFS capacity expressions with promtool, not a second
# copy of their selectors.
set -euo pipefail

directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
source="${directory}/rustfs-capacity-alert-rules.json"

jq -e 'length == 3 and all(.[];
  .condition == "C" and .ruleGroup == "RustFS" and .isPaused == false and
  .noDataState == "OK" and .execErrState == "KeepLast" and
  .data[0].datasourceUid == "cg3i1jh2k1v5sb" and
  (.labels.severity | IN("warning", "critical")) and
  (.data[] | select(.refId == "C") | .model | .expression == "A" and .type == "threshold"))' "${source}" >/dev/null

jq '{groups: [{name: "RustFS", interval: "1m", rules: map({
  alert: .uid,
  expr: ("(" + (.data[] | select(.refId == "A") | .model.expr) + ") "
    + ((.data[] | select(.refId == "C") | .model.conditions[0].evaluator) as $e
       | (if $e.type == "lt" then "< " else "> " end) + ($e.params[0] | tostring))),
  for: .for, labels: .labels
})}]}' "${source}" > "${temporary}/rules.json"

jq --arg rules "${temporary}/rules.json" '
  . as $ruleset
  | def encode: to_entries | map("\(.key)=\(.value | tojson)") | join(",");
    {cluster: "tuist-production", server: "rustfs-0.rustfs-peers:9000", drive: "/data0"} as $drive
    | {cluster: "tuist-production", namespace: "rustfs-production"} as $store
    | def series($free; $total; $replicas):
        ($drive + {job: "rustfs", instance: "rustfs-0"} | encode) as $d
        | [
            (if $free != null then {series: "rustfs_cluster_drive_free_bytes{\($d)}", values: "\($free)+0x40"} else empty end),
            (if $total != null then {series: "rustfs_cluster_drive_total_bytes{\($d)}", values: "\($total)+0x40"} else empty end),
            {series: "kube_statefulset_replicas{\($store + {statefulset: "rustfs", job: "kube-state-metrics"} | encode)}", values: "\($replicas)+0x40"},
            # Another StatefulSet in the namespace must not count as RustFS.
            {series: "kube_statefulset_replicas{\({cluster: "tuist-production", namespace: "rustfs-production", statefulset: "other", job: "kube-state-metrics"} | encode)}", values: "1+0x40"}
          ];
  [
    # name, free, total, replicas, firing at 20m
    ["healthy", 50, 100, 1, []],
    ["warning_boundary", 15, 100, 1, []],
    ["warning", 14, 100, 1, ["rustfs-drive-free-low"]],
    ["critical_boundary", 5, 100, 1, ["rustfs-drive-free-low"]],
    ["critical", 4, 100, 1, ["rustfs-drive-free-low", "rustfs-drive-free-critical"]],
    ["metrics_missing", null, null, 1, ["rustfs-drive-metrics-missing"]],
    ["total_only_is_not_missing", null, 100, 1, []],
    ["scaled_down_is_not_missing", null, null, 0, []]
  ]
  | map(
      . as [$name, $free, $total, $replicas, $firing]
      | {
          name: $name, interval: "1m",
          input_series: series($free; $total; $replicas),
          alert_rule_test: (
            [$ruleset[] | . as $rule | {
              eval_time: "20m", alertname: .uid,
              exp_alerts: (if ($firing | index($rule.uid)) != null then [{exp_labels: (
                (if $rule.uid == "rustfs-drive-metrics-missing" then $store else $drive end) + $rule.labels)}] else [] end)
            }]
            # The warning waits 15m and the critical 5m before firing.
            + [{eval_time: "4m", alertname: "rustfs-drive-free-critical", exp_alerts: []},
               {eval_time: "14m", alertname: "rustfs-drive-free-low", exp_alerts: []}])
        }
    )
  | {rule_files: [$rules], evaluation_interval: "1m", tests: .}
' "${source}" > "${temporary}/tests.json"

promtool check rules "${temporary}/rules.json"
promtool test rules "${temporary}/tests.json"
