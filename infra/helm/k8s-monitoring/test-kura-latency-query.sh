#!/usr/bin/env bash
# Run every shipped migration expression with distinct old/new distributions.
set -euo pipefail

directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROMTOOL="${PROMTOOL:-$(command -v promtool)}"
python3 - "${directory}" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

directory = Path(sys.argv[1])
metric = "kura_public_request_latency_by_transport_seconds_bucket"
queries = []


def visit(value):
    if isinstance(value, dict):
        expression = value.get("expr", "")
        if metric in expression:
            queries.append(expression)
        for child in value.values():
            visit(child)
    elif isinstance(value, list):
        for child in value:
            visit(child)


for name in ["tuist-kura-details", "tuist-kura-customer-overview", "tuist-kura-region-scalability"]:
    visit(json.loads((directory / "../../grafana-dashboards" / (name + ".json")).read_text()))
alerts = (directory / "alerts.md").read_text()
queries.append(re.search(r"### Kura public request latency high\s+```promql\n(.*?)\n```", alerts, re.S)[1])
assert len(queries) == 8, f"update the test for the changed migration query inventory: {len(queries)}"


def series(name, pod, extra, increments):
    return [{"series": f'{name}{{cluster="tuist-production",env="production",pod="{pod}",le="{le}",{extra}}}',
             "values": f"0+{increment}x10"}
            for le, increment in zip(["0.001", "0.01", "+Inf"], increments)]


old = series("kura_public_request_latency_seconds_bucket", "old", 'transport="http",route="/a"', [20, 40, 40])
old += series("kura_public_request_latency_seconds_bucket", "old", 'transport="grpc",route="/b"', [40, 80, 80])
new = series(metric, "new", 'transport="http"', [90, 100, 100])
new += series(metric, "new", 'transport="grpc"', [180, 200, 200])
partial = series("kura_public_request_latency_seconds_bucket", "new",
                 'transport="grpc",route="/SpliceBlob",latency_aggregate="true"', [200, 200, 200])
tests = []
for name, inputs, pods in [
    ("old_only", old, ["old"]),
    ("new_only", new + partial, ["new"]),
    ("mixed_rollout", old + new + partial, ["old", "new"]),
    ("mixed_region", old + new + partial, ["old", "new"]),
    ("runtime_rollback", old + partial, ["old"]),
]:
    inputs = list(inputs)
    for pod in pods:
        region = "shared" if name == "mixed_region" else pod
        labels = f'cluster="tuist-production",env="production",pod="{pod}",region="{region}",tenant_id="tenant"'
        inputs += [{"series": f"{info}{{{labels}}}", "values": "1+0x10"}
                   for info in ["kura_node_geo_info", "kura_node_info", "kura:pod_region"]]
        inputs.append({"series": f'kura_public_request_latency_seconds_count{{{labels}}}',
                       "values": "0+300x10"})
    expressions = []
    for query in queries:
        query = query.replace("$__rate_interval", "5m").replace("$__range", "5m")
        query = query.replace("$env", "production").replace("$pod", ".*").replace("$region", ".*")
        quantile = float(re.search(r"histogram_quantile\(([0-9.]+)", query)[1])
        expected = []
        for pod in pods:
            region = "shared" if name == "mixed_region" else pod
            regional = "sum by (cluster, region, le)" in query or "sum by (region, le)" in query
            if regional and name == "mixed_region" and pod == "new":
                continue
            fraction = (11 / 14 if regional and name == "mixed_region"
                        else 0.5 if pod == "old" else 0.9)
            value = (0.001 * quantile / fraction if quantile <= fraction
                     else 0.001 + 0.009 * (quantile - fraction) / (1 - fraction))
            if "sum by (tenant_id, region, pod, le)" in query:
                labels = f'{{tenant_id="tenant",region="{region}",pod="{pod}"}}'
            elif "sum by (cluster, region, le)" in query:
                labels = f'{{cluster="tuist-production",region="{region}"}}'
            elif "sum by (region, le)" in query:
                labels = f'{{region="{region}"}}'
            else:
                labels = f'{{pod="{pod}"}}'
            expected.append({"labels": labels, "value": round(value, 12)})
        expressions.append({"expr": f"round(({query}), 1e-12)", "eval_time": "5m", "exp_samples": expected})
    tests.append({"name": name, "interval": "1m", "input_series": inputs, "promql_expr_test": expressions})

with tempfile.TemporaryDirectory() as temporary:
    path = Path(temporary) / "tests.json"
    path.write_text(json.dumps({"rule_files": [], "fuzzy_compare": True,
                               "evaluation_interval": "1m", "tests": tests}))
    subprocess.run([os.environ["PROMTOOL"], "test", "rules", str(path)], check=True)
print(f"Validated {len(queries)} dashboard/alert expressions across {len(tests)} rollout states")
PY
