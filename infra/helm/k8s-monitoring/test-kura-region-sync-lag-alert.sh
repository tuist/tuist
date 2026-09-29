#!/usr/bin/env bash
# Exercise the shipped Grafana expression with the upstream Prometheus engine.
set -euo pipefail

directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT

rule="${directory}/kura-replication-alert-rules.json"

jq -e '
  .[0] as $rule
  | ($rule.data[] | select(.refId == $rule.condition) | .model) as $condition
  | $condition.type == "threshold" and $condition.expression == "A"
    and ($condition.conditions | length) == 1
    and $condition.conditions[0].evaluator == {params: [600], type: "gt"}
    and $rule.isPaused == false
    and $rule.ruleGroup == "Cache"
    and $rule.noDataState == "OK" and $rule.execErrState == "Error"
    and ($rule | has("notification_settings") | not)
    and $rule.labels == {severity: "warning"}
' "${rule}" > /dev/null

# The Cache group evaluates every five minutes; the tests evaluate at the same
# cadence against one-minute samples, close to Kura's 65-second scrape.
jq '
  .[0] as $rule
  | ($rule.data[] | select(.refId == "A") | .model.expr) as $query
  | {groups: [{name: $rule.ruleGroup, interval: "5m", rules: [{
      alert: "KuraRegionReplicationLagging", expr: "(\($query)) > 600",
      for: $rule.for, labels: $rule.labels
  }]}]}
' "${rule}" > "${temporary}/rules.json"

jq --arg rules "${temporary}/rules.json" '
  .[0] as $rule
  | ($rule.data[] | select(.refId == "A") | .model.expr) as $query
  | def series($cluster; $pod; $region; $values):
      {series: "kura_region_sync_lag_seconds{cluster=\"\($cluster)\",namespace=\"kura\",job=\"kura\",instance=\"kura/\($pod)\",pod=\"\($pod)\",region=\"\($region)\"}", values: $values};
    def lag($pod; $region; $values): series("tuist-production"; $pod; $region; $values);
    def fires($region): [{exp_labels: ({cluster: "tuist-production", namespace: "kura", statefulset: "kura-acme-eu-central", region: $region} + $rule.labels)}];
    def evals($pairs): $pairs | map({eval_time: .[0], alertname: "KuraRegionReplicationLagging", exp_alerts: .[1]});
  [
    # Caught up, including a remote region that writes nothing: zero throughout.
    {name: "caught_up", input_series: [lag("kura-acme-eu-central-0"; "us-east"; "0x60")],
     alert_rule_test: evals([["20m", []], ["40m", []], ["60m", []]])},
    # Ten minutes behind from minute 10 on: pending at 10m, firing two evaluations later.
    {name: "sustained", input_series: [lag("kura-acme-eu-central-0"; "us-east"; "0x9 700+60x50")],
     alert_rule_test: evals([["10m", []], ["15m", []], ["20m", fires("us-east")], ["40m", fires("us-east")]])},
    # A handover or backward pass that reports a large lag for four minutes.
    {name: "short_backward_pass", input_series: [lag("kura-acme-eu-central-0"; "us-east"; "0x9 5000x3 0x46")],
     alert_rule_test: evals([["15m", []], ["20m", []], ["30m", []]])},
    # The link cannot reach the remote gateway: the lag grows with the silence.
    {name: "unreachable", input_series: [lag("kura-acme-eu-central-0"; "us-east"; "0x9 0+60x50")],
     alert_rule_test: evals([["25m", []], ["30m", []], ["35m", fires("us-east")]])},
    # The gateway role moves from pod 0 to pod 1 and the series is absent at the
    # 20m evaluation. The window bridges it, so the alert neither resets nor doubles.
    {name: "role_hop", input_series: [
        lag("kura-acme-eu-central-0"; "us-east"; "0x9 700+60x7 stale"),
        lag("kura-acme-eu-central-1"; "us-east"; "_x21 1900+60x30")],
     alert_rule_test: evals([["15m", []], ["20m", fires("us-east")], ["30m", fires("us-east")]])},
    # Both pods briefly report during a handover: still one alert.
    {name: "overlapping_gateways", input_series: [
        lag("kura-acme-eu-central-0"; "us-east"; "0x9 700+60x50"),
        lag("kura-acme-eu-central-1"; "us-east"; "0x9 900+60x50")],
     alert_rule_test: evals([["20m", fires("us-east")]])},
    # Each remote region is its own link and its own alert.
    {name: "per_region", input_series: [
        lag("kura-acme-eu-central-0"; "us-east"; "0x9 700+60x50"),
        lag("kura-acme-eu-central-0"; "ap-south"; "0x60")],
     alert_rule_test: evals([["20m", fires("us-east")]])},
    # Non-production is out of scope.
    {name: "staging_ignored", input_series: [series("tuist-staging"; "kura-acme-eu-central-0"; "us-east"; "0x9 700+60x50")],
     alert_rule_test: evals([["20m", []]]),
     promql_expr_test: [{expr: $query, eval_time: "20m", exp_samples: []}]}
  ]
  | map(. + {interval: "1m"})
  | {rule_files: [$rules], evaluation_interval: "5m", tests: .}
' "${rule}" > "${temporary}/tests.json"

promtool check rules "${temporary}/rules.json"
promtool test rules "${temporary}/tests.json"
