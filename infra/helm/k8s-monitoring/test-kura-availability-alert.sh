#!/usr/bin/env bash
# Exercise the shipped Grafana expression and policy with the upstream engines.
set -euo pipefail

directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT

rule="${directory}/kura-availability-alert-rules.json"
amtool="${AMTOOL:-amtool}"

jq -e '
  .[0] as $rule
  | ($rule.data[] | select(.refId == $rule.condition) | .model) as $condition
  | $condition.type == "threshold" and $condition.expression == "A"
    and ($condition.conditions | length) == 1
    and $condition.conditions[0].evaluator == {params: [0], type: "gt"}
    and $rule.isPaused == false
    and $rule.ruleGroup == "Cache availability"
    and $rule.noDataState == "NoData" and $rule.execErrState == "Error"
    and ($rule | has("notification_settings") | not)
    and $rule.labels.affected_service == "Cache"
' "${rule}" > /dev/null

jq '
  .[0] as $rule
  | ($rule.data[] | select(.refId == "A") | .model.expr) as $query
  | {groups: [{name: $rule.ruleGroup, interval: "1m", rules: [{
      alert: "KuraInstanceHasNoReadyReplicas", expr: "(\($query)) > 0",
      for: $rule.for, labels: $rule.labels
  }]}]}
' "${rule}" > "${temporary}/rules.json"

jq --arg rules "${temporary}/rules.json" '
  .[0] as $rule
  | ($rule.data[] | select(.refId == "A") | .model.expr) as $query
  | [
      ["healthy", "2+0x6", "2+0x6", false, false],
      ["one_ready", "2+0x6", "1+0x6", false, false],
      ["outage", "2+0x6", "0+0x6", false, true],
      ["scaled_down", "0+0x6", "0+0x6", false, false],
      ["brief_rollout", "2+0x6", "2 0 2 2 2 2 2", false, false],
      ["recovered", "2+0x6", "0 0 0 2 2 2 2", true, false]
    ]
  | map(
      . as [$name, $desired, $ready, $fires_at_2m, $fires_at_4m]
      | {cluster: "tuist-production", namespace: "kura", statefulset: $name} as $labels
      | ($labels | to_entries | map("\(.key)=\(.value | tojson)") | join(",")) as $encoded
      | {
          name: $name, interval: "1m",
          input_series: [
            {series: "kube_statefulset_replicas{\($encoded)}", values: $desired},
            {series: "kube_statefulset_status_replicas_ready{\($encoded)}", values: $ready}
          ],
          alert_rule_test: (
            [["1m", false], ["2m", ($fires_at_2m or $fires_at_4m)], ["4m", $fires_at_4m]]
            | map({
                eval_time: .[0], alertname: "KuraInstanceHasNoReadyReplicas",
                exp_alerts: (if .[1] then [{exp_labels: ($labels + $rule.labels)}] else [] end)
            })
          )
      }
    )
  | . + [
      {
        name: "missing_and_unrelated_series", interval: "1m",
        input_series: [
          {series: "kube_statefulset_replicas{namespace=\"kura\",statefulset=\"missing\"}", values: "2+0x6"},
          {series: "kube_statefulset_replicas{namespace=\"other\",statefulset=\"other\"}", values: "2+0x6"},
          {series: "kube_statefulset_status_replicas_ready{namespace=\"other\",statefulset=\"other\"}", values: "0+0x6"}
        ],
        promql_expr_test: [{expr: $query, eval_time: "4m", exp_samples: []}]
      },
      {
        name: "cluster_label_absent", interval: "1m",
        input_series: [
          {series: "kube_statefulset_replicas{namespace=\"kura\",statefulset=\"no-cluster\"}", values: "2+0x6"},
          {series: "kube_statefulset_status_replicas_ready{namespace=\"kura\",statefulset=\"no-cluster\"}", values: "0+0x6"}
        ],
        alert_rule_test: [{
          eval_time: "2m", alertname: "KuraInstanceHasNoReadyReplicas",
          exp_alerts: [{exp_labels: ({namespace: "kura", statefulset: "no-cluster"} + $rule.labels)}]
        }]
      }
    ]
  | {rule_files: [$rules], evaluation_interval: "1m", tests: .}
' "${rule}" > "${temporary}/tests.json"

promtool check rules "${temporary}/rules.json"
promtool test rules "${temporary}/tests.json"

# Keep the existing staging exceptions ahead of the new sibling routes.
# amtool tests the actual sibling/continue semantics without sending notifications.
jq '
  def alertmanager_route:
    . as $route
    | del(.object_matchers, .routes)
    + (if $route | has("object_matchers") then
        {matchers: ($route.object_matchers | map("\(.[0])\(.[1])\(.[2] | tojson)"))}
      else {} end)
    + (if $route | has("routes") then {routes: ($route.routes | map(alertmanager_route))} else {} end);
  {
    route: {receiver: "Slack #notifications 2", routes: ([
      {receiver: "Slack #notifications-non-prod", matchers: ["cluster=\"tuist-staging\""]},
      {receiver: "Slack #notifications-non-prod", matchers: ["env=\"staging\""]}
    ] + map(alertmanager_route))},
    receivers: (["Slack #notifications 2", "Slack #notifications-non-prod", "Incidents"] | map({name: .}))
  }
' "${directory}/kura-availability-notification-policy.json" > "${temporary}/routing.json"

test_route() {
  local name="$1" overrides="$2" receivers="$3" label
  local labels=()
  jq -r --argjson overrides "${overrides}" '
    {alertname: .[0].title, grafana_folder: "Alerts"} + $overrides
    | to_entries[] | "\(.key)=\(.value | tojson)"
  ' "${rule}" > "${temporary}/labels.txt"
  while IFS= read -r label; do
    labels+=("${label}")
  done < "${temporary}/labels.txt"
  echo "Routing: ${name}"
  "${amtool}" config routes test \
    "--config.file=${temporary}/routing.json" "--verify.receivers=${receivers}" "${labels[@]}"
}

test_route production '{"cluster":"tuist-production"}' 'Slack #notifications 2,Incidents'
test_route staging '{"cluster":"tuist-staging"}' 'Slack #notifications-non-prod'
test_route canary '{"cluster":"tuist-canary"}' 'Slack #notifications-non-prod'
test_route missing_cluster '{}' 'Slack #notifications-non-prod'
test_route unknown_cluster '{"cluster":"other"}' 'Slack #notifications-non-prod'
test_route env_only '{"env":"production"}' 'Slack #notifications-non-prod'
test_route staging_with_production_env '{"cluster":"tuist-staging","env":"production"}' 'Slack #notifications-non-prod'
test_route production_with_staging_env '{"cluster":"tuist-production","env":"staging"}' 'Slack #notifications-non-prod'
test_route unrelated_rule '{"alertname":"Unrelated","cluster":"tuist-production"}' 'Slack #notifications 2'
test_route unrelated_folder '{"grafana_folder":"Other","cluster":"tuist-production"}' 'Slack #notifications 2'
