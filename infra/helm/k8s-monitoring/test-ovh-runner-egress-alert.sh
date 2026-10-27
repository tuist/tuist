#!/usr/bin/env bash
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
jq '
  {groups: [{name: "Runner networking", interval: "1m", rules: map({
    alert: .uid, expr: "(" + .data[0].model.expr + ") > 0.8", for: .for, labels: .labels
  })}]}
' "${directory}/ovh-runner-egress-alert-rules.json" > "${temporary}/rules.json"
jq --arg rules "${temporary}/rules.json" '
  .[0].data[0].model.expr as $query
  | {rule_files: [$rules], evaluation_interval: "1m", tests: [{
    interval: "1m", input_series: [
      {series: "node_network_transmit_bytes_total{cluster=\"production\",instance=\"a\",device=\"private0\"}", values: "0+18000000000x20"},
      {series: "node_network_transmit_bytes_total{cluster=\"production\",instance=\"b\",device=\"private1\"}", values: "0+18000000000x20"},
      {series: "node_network_transmit_bytes_total{cluster=\"production\",instance=\"a\",device=\"public0\"}", values: "0+600000000000x20"},
      {series: "node_network_info{cluster=\"production\",instance=\"a\",device=\"private0\",address=\"aa:01\"}", values: "1+0x20"},
      {series: "node_network_info{cluster=\"production\",instance=\"b\",device=\"private1\",address=\"bb:01\"}", values: "1+0x20"},
      {series: "node_network_info{cluster=\"production\",instance=\"a\",device=\"public0\",address=\"cc:01\"}", values: "1+0x20"},
      {series: "capt_runner_egress_info{cluster=\"production\",node=\"a\",mac=\"aa:01\",vrack=\"pn-123\",cidr=\"198.51.100.0/27\"}", values: "1+0x20"},
      {series: "capt_runner_egress_info{cluster=\"production\",node=\"b\",mac=\"bb:01\",vrack=\"pn-123\",cidr=\"198.51.100.0/27\"}", values: "1+0x20"},
      {series: "node_network_transmit_bytes_total{cluster=\"staging\",instance=\"a\",device=\"private0\"}", values: "0+600000000x20"},
      {series: "node_network_info{cluster=\"staging\",instance=\"a\",device=\"private0\",address=\"aa:01\"}", values: "1+0x20"},
      {series: "capt_runner_egress_info{cluster=\"staging\",node=\"a\",mac=\"aa:01\",vrack=\"pn-124\",cidr=\"198.51.100.32/29\"}", values: "1+0x20"}
    ],
    promql_expr_test: [{expr: $query, eval_time: "5m", exp_samples: [
      {labels: "{cluster=\"production\",vrack=\"pn-123\",cidr=\"198.51.100.0/27\"}", value: 0.96},
      {labels: "{cluster=\"staging\",vrack=\"pn-124\",cidr=\"198.51.100.32/29\"}", value: 0.016}
    ]}],
    alert_rule_test: [
      {eval_time: "5m", alertname: "ovh-runner-vrack-transmit", exp_alerts: []},
      {eval_time: "15m", alertname: "ovh-runner-vrack-transmit", exp_alerts: [{exp_labels: {
        cluster: "production", vrack: "pn-123", cidr: "198.51.100.0/27", severity: "warning", affected_service: "Runners"
      }}]},
      {eval_time: "15m", alertname: "ovh-runner-vrack-receive", exp_alerts: []}
    ]
  }]}
' "${directory}/ovh-runner-egress-alert-rules.json" > "${temporary}/tests.json"
promtool check rules "${temporary}/rules.json"
promtool test rules "${temporary}/tests.json"
