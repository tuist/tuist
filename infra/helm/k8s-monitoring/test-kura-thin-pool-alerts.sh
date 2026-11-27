#!/usr/bin/env bash
# Exercise the shipped thin pool expressions and paging policy with the
# upstream engines (promtool and amtool), without sending notifications.
set -euo pipefail

directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT

source="${directory}/kura-thin-pool-alert-rules.json"
policy="${directory}/kura-thin-pool-notification-policy.json"
promtool="${PROMTOOL:-promtool}"
amtool="${AMTOOL:-amtool}"

# Policy routing only: paging comes from the notification policy, so staging
# and canary never page.
jq -e 'length == 8 and all(.[];
  .condition == "C" and .ruleGroup == "Kura thin pools" and .isPaused == false and
  .noDataState == "OK" and .execErrState == "KeepLast" and
  (has("notification_settings") | not) and
  (.labels.severity | IN("warning", "critical")) and
  (.data[] | select(.refId == "C") | .model |
    .expression == "A" and .type == "threshold" and .conditions[0].evaluator.type == "gt"))' "${source}" >/dev/null
jq -e --slurpfile rules "${source}" '
  ($rules[0] | map(select(.labels.severity == "critical") | .title) | sort) as $paging
  | all(.[]; (.object_matchers[0] | .[0] == "alertname" and .[1] == "=~")
             and (.object_matchers[0][2] | split("|") | sort) == $paging)
' "${policy}" >/dev/null
# test-pulse-environment-copies.sh keeps the other copies in step with these.
jq 'map(select(.data[0].datasourceUid == "cg3i1jh2k1v5sb"))' "${source}" > "${temporary}/production.json"
source="${temporary}/production.json"

jq '{groups: [{name: "Kura thin pools", interval: "1m", rules: map({
  alert: .uid,
  expr: ("(" + (.data[] | select(.refId == "A") | .model.expr) + ") > "
    + (.data[] | select(.refId == "C") | .model.conditions[0].evaluator.params[0] | tostring)),
  for: .for, labels: .labels
})}]}' "${source}" > "${temporary}/rules.json"

jq --arg rules "${temporary}/rules.json" '
  . as $ruleset
  | ($ruleset | map(.uid)) as $uids
  | def encode: to_entries | map("\(.key)=\(.value | tojson)") | join(",");
    def ready($node; $ready):
      {series: "kube_node_labels{\({cluster: "tuist-production", node: $node, job: "kube-state-metrics"}
        + (if $ready then {label_tuist_dev_kura_thin_ready: "true"} else {} end) | encode)}", values: "1+0x400"};
    def kura_node($node; $node_pool; $ready):
      {series: "kube_node_labels{\({cluster: "tuist-production", node: $node, job: "kube-state-metrics",
        label_node_cluster_x_k8s_io_pool: $node_pool}
        + (if $ready then {label_tuist_dev_kura_thin_ready: "true"} else {} end) | encode)}", values: "1+0x400"};
    def pool($labels; $data; $metadata; $ro; $full; $healthy; $observed):
      ($labels + {job: "kura-volumes-csi-node", pod: "kura-volumes-csi-node-abcde"} | encode) as $encoded
      | [
          {series: "kura_volumes_thin_pool_data_size_bytes{\($encoded)}", values: "100+0x400"},
          {series: "kura_volumes_thin_pool_data_used_bytes{\($encoded)}", values: "\($data)+0x400"},
          {series: "kura_volumes_thin_pool_metadata_size_bytes{\($encoded)}", values: "100+0x400"},
          {series: "kura_volumes_thin_pool_metadata_used_bytes{\($encoded)}", values: "\($metadata)+0x400"},
          {series: "kura_volumes_thin_pool_read_only{\($encoded)}", values: "\($ro)+0x400"},
          {series: "kura_volumes_thin_pool_out_of_data_space{\($encoded)}", values: "\($full)+0x400"},
          {series: "kura_volumes_thin_pool_healthy{\($encoded)}", values: "\($healthy)+0x400"},
          {series: "kura_volumes_thin_pool_last_observation_timestamp_seconds{\($encoded)}", values: $observed}
        ];
    def expect($time; $firing; $labels):
      $ruleset[] | . as $rule | {
        eval_time: $time, alertname: .uid,
        exp_alerts: (if ($firing | index($rule.uid)) != null then [{exp_labels: ($labels
          + (if $rule.uid | IN("kura-thin-pool-metrics-missing", "kura-thin-pool-node-unprepared") then {}
             else {vg: "kura-volumes", pool: "kura-thin"} end)
          + $rule.labels)}] else [] end)
      };
  # Full data inside backed ceilings is a healthy, full cache: only the plugin
  # healthy gauge says the pool cannot back its volumes.
  [
    ["healthy", 50, 50, 0, 0, 1, []],
    ["full_cache_backed", 95, 50, 0, 0, 1, []],
    ["unbacked", 95, 50, 0, 0, 0, ["kura-thin-pool-unhealthy"]],
    ["below_metadata_warning", 50, 69, 0, 0, 1, []],
    ["metadata_warning", 50, 75, 0, 0, 1, ["kura-thin-pool-metadata-high"]],
    ["metadata_page", 50, 90, 0, 0, 0, ["kura-thin-pool-unhealthy", "kura-thin-pool-metadata-high", "kura-thin-pool-metadata-full"]],
    ["read_only", 50, 50, 1, 0, 0, ["kura-thin-pool-unhealthy", "kura-thin-pool-degraded"]],
    ["out_of_data_space", 100, 50, 0, 1, 0, ["kura-thin-pool-unhealthy", "kura-thin-pool-degraded"]]
  ]
  | map(
      . as [$name, $data, $metadata, $ro, $full, $healthy, $firing]
      | {cluster: "tuist-production", node: $name} as $labels
      | {
          name: $name, interval: "1m",
          input_series: ([ready($name; true)] + pool($labels + {vg: "kura-volumes", pool: "kura-thin"}; $data; $metadata; $ro; $full; $healthy; "0+60x40")),
          alert_rule_test: ([expect("1m"; []; $labels)] + [expect("20m"; $firing; $labels)])
        }
    )
  | . + (
      [
        ["ready_without_metrics", true, false, "0+60x40", ["kura-thin-pool-metrics-missing"]],
        ["ready_with_stale_observation", true, true, "0+0x400", ["kura-thin-pool-metrics-missing"]],
        ["ready_with_fresh_observation", true, true, "0+60x40", []],
        ["unlabelled_without_metrics", false, false, "0+60x40", []]
      ]
      | map(
          . as [$name, $ready, $metrics, $observed, $firing]
          | {cluster: "tuist-production", node: $name} as $labels
          | {
              name: $name, interval: "1m",
              input_series: ([ready($name; $ready)]
                + (if $metrics then pool($labels + {vg: "kura-volumes", pool: "kura-thin"}; 50; 50; 0; 0; 1; $observed) else [] end)),
              alert_rule_test: ([expect("5m"; []; $labels)] + [expect("30m"; $firing; $labels)])
            }
        )
    )
  # Thin-enrolled regions select tuist.dev/kura-thin-ready, so a Kura pool
  # node without it holds stranded disk; other pools do not run Kura.
  | . + (
      [
        ["kura_node_unprepared", "kura-us-east", false, ["kura-thin-pool-node-unprepared"]],
        ["kura_node_qualified", "kura-us-east", true, []],
        ["other_pool_unlabelled", "runners", false, []]
      ]
      | map(
          . as [$name, $node_pool, $ready, $firing]
          | {cluster: "tuist-production", node: $name} as $labels
          | {
              name: $name, interval: "1m",
              input_series: ([kura_node($name; $node_pool; $ready)]
                + (if $ready then pool($labels + {vg: "kura-volumes", pool: "kura-thin"}; 50; 50; 0; 0; 1; "0+60x400") else [] end)),
              alert_rule_test: ([expect("5h50m"; []; $labels)]
                + [expect("6h10m"; $firing; $labels + {label_node_cluster_x_k8s_io_pool: $node_pool})])
            }
        )
    )
  | . + [{name: "no_series", interval: "1m", input_series: [],
      alert_rule_test: [$uids[] | {eval_time: "30m", alertname: ., exp_alerts: []}]}]
  | {rule_files: [$rules], evaluation_interval: "1m", tests: .}
' "${source}" > "${temporary}/tests.json"

"${promtool}" check rules "${temporary}/rules.json"
"${promtool}" test rules "${temporary}/tests.json"

# The live tree's staging exceptions stay ahead of these sibling routes, as in
# test-kura-availability-alert.sh.
jq '
  def alertmanager_route:
    . as $route
    | del(.object_matchers, .routes)
    + (if $route | has("object_matchers") then
        {matchers: ($route.object_matchers | map("\(.[0])\(.[1])\(.[2] | tojson)"))}
      else {} end);
  {
    route: {receiver: "Slack #notifications 2", routes: ([
      {receiver: "Slack #notifications-non-prod", matchers: ["cluster=\"tuist-staging\""]},
      {receiver: "Slack #notifications-non-prod", matchers: ["env=\"staging\""]}
    ] + map(alertmanager_route))},
    receivers: (["Slack #notifications 2", "Slack #notifications-non-prod", "Incidents"] | map({name: .}))
  }
' "${policy}" > "${temporary}/routing.json"

test_route() {
  local name="$1" uid="$2" cluster="$3" receivers="$4"
  local title
  title="$(jq -r --arg uid "${uid}" '.[] | select(.uid == $uid) | .title' "${source}")"
  echo "Routing: ${name}"
  "${amtool}" config routes test "--config.file=${temporary}/routing.json" "--verify.receivers=${receivers}" \
    "alertname=\"${title}\"" 'grafana_folder="Alerts"' "cluster=\"${cluster}\""
}

for uid in kura-thin-pool-unhealthy kura-thin-pool-metadata-full kura-thin-pool-degraded; do
  test_route "${uid} production" "${uid}" tuist-production 'Slack #notifications 2,Incidents'
  test_route "${uid} staging" "${uid}" tuist-staging 'Slack #notifications-non-prod'
  test_route "${uid} canary" "${uid}" tuist-canary 'Slack #notifications-non-prod'
done
for uid in kura-thin-pool-metadata-high kura-thin-pool-metrics-missing kura-thin-pool-node-unprepared; do
  test_route "${uid} production" "${uid}" tuist-production 'Slack #notifications 2'
  test_route "${uid} staging" "${uid}" tuist-staging 'Slack #notifications-non-prod'
done
