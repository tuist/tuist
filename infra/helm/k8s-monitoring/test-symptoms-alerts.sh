#!/usr/bin/env bash
# Test the Prometheus expressions of the Symptoms watcher and backstop rules
# with Prometheus's rule engine. The Pulse comparison rules mix Pulse SQL and
# Loki queries, so only their shape is checked here.
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
watchers="${directory}/symptoms-alert-rules.json"
backstops="${directory}/symptoms-backstop-alert-rules.json"

jq -e -s 'add | all(.[];
  .noDataState == "OK" and .execErrState == "Error" and (.labels.severity | IN("warning", "critical")) and
  (if .labels.severity == "critical"
   then .notification_settings.receiver == "Incidents" and (.labels.affected_service | type == "string")
   else has("notification_settings") | not end))' "${watchers}" "${backstops}" >/dev/null
jq -e 'map(select(.uid | startswith("symptoms-pulse-"))) | length == 2 and all(.[];
  .condition == "D" and ([.data[].datasourceUid] | .[0] == "pulse-sql"))' "${watchers}" >/dev/null

# A threshold rule is "A <op> value"; the burn-rate rules are "A > 14.4 and
# B > 14.4" over the same labels.
jq -s '{groups: [{name: "Symptoms", interval: "1m", rules: (add | map(
  select(.data | all(.datasourceUid | IN("grafanacloud-prom", "__expr__")))) | map(
  (.data | map({(.refId): .model}) | add) as $q |
  ($q[.condition]) as $c |
  {alert: .uid, for: .for, labels: .labels, expr:
    (if $c.type == "threshold" then
       "(\($q.A.expr)) \({gt: ">", lt: "<"}[$c.conditions[0].evaluator.type]) \($c.conditions[0].evaluator.params[0])"
     elif $c.expression == "$A > 14.4 && $B > 14.4" then
       "(\($q.A.expr)) > 14.4 and (\($q.B.expr)) > 14.4"
     else error("unsupported condition in \(.uid)") end)}))}]}' \
  "${watchers}" "${backstops}" > "${temporary}/rules.json"

# Each case: rule, input series as [series, values], whether it fires at
# 40 minutes, and the labels it fires with.
jq -n --arg rules "${temporary}/rules.json" '
  def p: "cluster=\"tuist-production\"";
  def hb($window): "symptoms_pipeline_last_success_timestamp_seconds{window_seconds=\"\($window)\"";
  def lag($window): "symptoms_pipeline_lag_seconds{window_seconds=\"\($window)\"";
  def ingress($selector; $total; $errors): [
    ["nginx_ingress_controller_requests{\(p),\($selector),status=\"200\"}", "0+\(($total - $errors) * 60)x60"],
    ["nginx_ingress_controller_requests{\(p),\($selector),status=\"502\"}", "0+\($errors * 60)x60"]];
  def server: "namespace=\"tuist\",ingress=\"tuist-tuist-server\"";
  def cache: "job=\"kura-ingress-nginx\",kura_gateway=\"eu-central\"";
  def probes($job; $instance; $results): [range(0; $results | length) as $i |
    ["probe_success{job=\"\($job)\",instance=\"\($instance)\",probe=\"p\($i)\"}", "\($results[$i])x60"]];
  [
    ["heartbeat_fresh", "symptoms-heartbeat-stale", [["\(hb("60")),\(p)}", "0+60x60"]], null],
    ["heartbeat_stuck", "symptoms-heartbeat-stale", [["\(hb("60")),\(p)}", "0+60x10 600x50"]], {cluster: "tuist-production"}],
    # Only the 1-minute pipeline is the heartbeat.
    ["heartbeat_other_window_stuck", "symptoms-heartbeat-stale", [["\(hb("60")),\(p)}", "0+60x60"], ["\(hb("300")),\(p)}", "0x60"]], null],
    ["heartbeat_present", "symptoms-heartbeat-missing", [["\(hb("60")),\(p)}", "0+60x60"]], null],
    ["heartbeat_absent", "symptoms-heartbeat-missing", [["\(hb("300")),\(p)}", "0+60x60"], ["symptoms_up{\(p)}", "0x60"]], {cluster: "tuist-production", window_seconds: "60"}],
    ["up", "symptoms-down", [["symptoms_up{\(p)}", "1x60"]], null],
    ["database_down", "symptoms-down", [["symptoms_up{\(p)}", "1x10 0x50"]], {cluster: "tuist-production"}],
    ["coverage_ok", "symptoms-coverage-low", [["symptoms_coverage_ratio{\(p)}", "0.95x60"]], null],
    ["coverage_low", "symptoms-coverage-low", [["symptoms_coverage_ratio{\(p)}", "0.5x60"]], {cluster: "tuist-production"}],
    ["source_fresh", "symptoms-source-stale", [["symptoms_source_freshness_seconds{\(p),source=\"pulse_traces\"}", "90x60"]], null],
    ["source_stale", "symptoms-source-stale", [["symptoms_source_freshness_seconds{\(p),source=\"pulse_logs\"}", "1200x60"], ["symptoms_source_freshness_seconds{\(p),source=\"pulse_traces\"}", "90x60"]], {cluster: "tuist-production", source: "pulse_logs"}],
    ["watching", "symptoms-nothing-watched", [["symptoms_sources_configured{\(p)}", "9x60"], ["symptoms_entities_expected{\(p)}", "1200x60"]], null],
    # Coverage reads 1 in both cases below, so only this rule notices.
    ["no_sources", "symptoms-nothing-watched", [["symptoms_sources_configured{\(p)}", "0x60"], ["symptoms_entities_expected{\(p)}", "1200x60"]], {cluster: "tuist-production"}],
    ["no_entities", "symptoms-nothing-watched", [["symptoms_sources_configured{\(p)}", "9x60"], ["symptoms_entities_expected{\(p)}", "0x60"]], {cluster: "tuist-production"}],
    ["streams_enabled", "symptoms-streams-disabled", [["symptoms_streams_disabled{\(p)}", "0x60"]], null],
    ["streams_disabled", "symptoms-streams-disabled", [["symptoms_streams_disabled{\(p)}", "2x60"]], {cluster: "tuist-production"}],
    # A 5-minute window normally ends up to 10 minutes back.
    ["lag_small", "symptoms-pipeline-lag", [["\(lag("60")),\(p)}", "60x60"], ["\(lag("300")),\(p)}", "540x60"]], null],
    ["lag_large", "symptoms-pipeline-lag", [["\(lag("60")),\(p)}", "900x60"]], {cluster: "tuist-production"}],
    ["server_one_percent", "server-ingress-slo-fast-burn", ingress(server; 100; 1), null],
    ["server_two_percent", "server-ingress-slo-fast-burn", ingress(server; 100; 2), {cluster: "tuist-production"}],
    ["cache_two_percent", "cache-ingress-slo-fast-burn", ingress(cache; 100; 2), {cluster: "tuist-production", kura_gateway: "eu-central"}],
    ["cache_idle_region", "cache-ingress-slo-fast-burn", ingress(cache; 0.5; 0.25), null],
    ["registry_one_failing", "registry-probe-failing", probes("tuist-registry-readiness"; "https://registry.tuist.dev/up"; [1, 1, 0]), null],
    ["registry_two_failing", "registry-probe-failing", probes("tuist-registry-readiness"; "https://registry.tuist.dev/up"; [1, 0, 0]), {}],
    ["registry_absent", "registry-probe-missing", [["up{\(p)}", "1x60"]], {job: "tuist-registry-readiness"}],
    ["kura_region_ok", "kura-region-probe-failing", probes("kura-region-readiness"; "eu-central"; [1, 1, 0]), null],
    ["kura_region_down", "kura-region-probe-failing", probes("kura-region-readiness"; "eu-central"; [0, 0, 1]), {instance: "eu-central"}],
    ["kura_region_absent", "kura-region-probe-missing", [["up{\(p)}", "1x60"]], {job: "kura-region-readiness"}]
  ] | map(. as [$name, $uid, $series, $labels] | {
    name: $name, interval: "1m",
    input_series: [$series[] | {series: .[0], values: .[1]}],
    alert_rule_test: [{eval_time: "40m", alertname: $uid, exp_alerts:
      (if $labels == null then [] else [{exp_labels: $labels}] end)}]
  }) | {rule_files: [$rules], evaluation_interval: "1m", tests: .}
' > "${temporary}/tests.json"

# exp_labels must list every label, so add the rules' own labels.
jq --slurpfile rules "${temporary}/rules.json" '
  ($rules[0].groups[0].rules | map({(.alert): .labels}) | add) as $own |
  .tests |= map(.alert_rule_test |= map(.alertname as $a |
    .exp_alerts |= map(.exp_labels = ($own[$a] + .exp_labels))))
' "${temporary}/tests.json" > "${temporary}/tests-labelled.json"

promtool check rules "${temporary}/rules.json"
promtool test rules "${temporary}/tests-labelled.json"
