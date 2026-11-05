#!/usr/bin/env bash
# Test the remote execution rules' expressions with Prometheus's rule engine.
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
source="${directory}/remote-execution-alert-rules.json"

jq -e 'length == 4 and all(.[];
  .condition == "C" and .labels.severity == "warning" and
  .noDataState == "OK" and .execErrState == "Error" and .notification_settings == null and
  (.data[] | select(.refId == "C") | .model | .expression == "A" and .type == "threshold"))' "${source}" >/dev/null

# Each rule is "A > threshold", which is one PromQL condition.
jq '{groups: [{name: "Remote execution", interval: "1m", rules: map(
  (.data[] | select(.refId == "C") | .model.conditions[0].evaluator.params[0]) as $threshold |
  {alert: .uid, expr: "(\(.data[] | select(.refId == "A") | .model.expr)) > \($threshold)",
   for: .for, labels: .labels}
)}]}' "${source}" > "${temporary}/rules.json"

# Each case: the rule, per-minute counter increments as [metric, label, value,
# increment] split over two pods, and whether the rule fires once its window
# and pending period have passed.
jq -n --arg rules "${temporary}/rules.json" '
  def gateway: ["remote-execution-gateway-errors", "reapi_gateway_executions_total", "code"];
  def queue: ["remote-execution-queue-full", "tuist_remote_execution_submissions_total", "outcome"];
  def prepare: ["remote-execution-vm-preparation-failing", "tuist_remote_execution_prepare_duration_milliseconds_count", "outcome"];
  def lease: ["remote-execution-lease-timeouts", "tuist_remote_execution_leases_total", "outcome"];
  [
    ["server_errors", gateway, [["Internal", 1], ["OK", 9]], true],
    ["at_five_percent", gateway, [["Unavailable", 1], ["OK", 19]], false],
    ["client_errors", gateway, [["FailedPrecondition", 5], ["DeadlineExceeded", 2], ["Canceled", 2], ["OK", 1]], false],
    ["too_few_calls", gateway, [["Internal", 1]], false],
    ["queue_full", queue, [["queue_full", 0.5], ["accepted", 10]], true],
    ["accepted_only", queue, [["accepted", 10], ["deduplicated", 3]], false],
    ["no_node", prepare, [["no_node", 1], ["ok", 0.5]], true],
    ["at_half", prepare, [["failed", 1], ["ok", 1]], false],
    ["own_cap_left_out", prepare, [["at_capacity", 10], ["ok", 1]], false],
    ["few_failures", prepare, [["failed", 0.2]], false],
    ["lease_timeouts", lease, [["timeout", 2], ["claimed", 1]], true],
    ["mostly_claimed", lease, [["timeout", 1], ["claimed", 2]], false],
    ["few_timeouts", lease, [["timeout", 0.5]], false]
  ] | map(
    . as [$name, [$uid, $metric, $label], $rates, $firing] |
    {
      name: $name, interval: "1m",
      input_series: [$rates[] as [$value, $rate] | ("a", "b") as $pod | {
        series: "\($metric){cluster=\"tuist-production\",pod=\"\($pod)\",\($label)=\"\($value)\"}",
        values: "0+\($rate / 2)x120"
      }],
      alert_rule_test: [
        {eval_time: "5m", alertname: $uid, exp_alerts: []},
        {eval_time: "60m", alertname: $uid, exp_alerts:
          (if $firing then [{exp_labels: {cluster: "tuist-production", severity: "warning"}}] else [] end)}
      ]
    }
  ) | {rule_files: [$rules], evaluation_interval: "1m", tests: .}
' > "${temporary}/tests.json"
promtool check rules "${temporary}/rules.json"
promtool test rules "${temporary}/tests.json"
