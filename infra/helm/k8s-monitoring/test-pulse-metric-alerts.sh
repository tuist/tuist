#!/usr/bin/env bash
# Check the retention-query rewrite without contacting a telemetry destination.
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROMTOOL="${PROMTOOL:-$(command -v promtool)}"
python3 - "${directory}" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

directory = Path(sys.argv[1])
rules = json.loads((directory / "pulse-metric-alert-queries.json").read_text())["rules"]
tests = []
for rule in rules:
    window = "3d" if rule["uid"] == "ps-dfygid92hevi8d" else "1d"
    original = f'''histogram_quantile(0.5,
      sum by (cluster, region, tenant_id, pod, le) (
        increase(kura_segment_shed_age_seconds_bucket{{cluster="tuist-production"}}[{window}])
        * on (cluster, pod) group_left(region, tenant_id)
          max by (cluster, pod, region, tenant_id) (kura_node_geo_info{{cluster="tuist-production"}})
      )
    ) and on (cluster, pod) (
      min by (cluster, pod) (
        min_over_time(kura_backfill_ring_fullness_percent{{cluster="tuist-production"}}[{window}])
      ) >= 100
    )'''
    optimized = rule["queries"]["A"]
    labels = 'cluster="tuist-production",pod="busy"'
    output = '{cluster="tuist-production",pod="busy",region="eu",tenant_id="account"}'
    for case in ["full", "not_full", "not_full_36h_ago", "missing_geo", "counter_reset"]:
        inputs = []
        for source, increments in [("a", [1, 2, 2]), ("b", [0, 6, 8])]:
            for le, increment in zip(["100", "1000", "+Inf"], increments):
                # A reset in only one source distinguishes increase-then-sum
                # from the incorrect sum-then-increase rewrite.
                values = (f"0+{increment}x35 0+{increment}x36"
                          if case == "counter_reset" and source == "a"
                          else f"0+{increment}x72")
                inputs.append({"series": f'kura_segment_shed_age_seconds_bucket{{{labels},le="{le}",instance="{source}"}}',
                               "values": values})
        inputs.append({"series": f'kura_backfill_ring_fullness_percent{{{labels}}}',
                       "values": {
                           "not_full": "100+0x60 99 100+0x11",
                           # At hour 72, this dip is outside 1d but inside 3d.
                           "not_full_36h_ago": "100+0x35 99 100+0x35",
                       }.get(case, "100+0x72")})
        if case != "missing_geo":
            inputs.append({"series": f'kura_node_geo_info{{{labels},region="eu",tenant_id="account"}}',
                           "values": "1+0x72"})
        checks = [
            {"expr": f"({original}) != ({optimized})", "eval_time": "72h", "exp_samples": []},
            {"expr": f"({original}) unless ({optimized})", "eval_time": "72h", "exp_samples": []},
            {"expr": f"({optimized}) unless ({original})", "eval_time": "72h", "exp_samples": []},
        ]
        if case == "full" or (case == "not_full_36h_ago" and window == "1d"):
            # Summed bucket counts are proportional to [1, 8, 10].
            # The median is 100 + (5 - 1) / (8 - 1) * 900.
            checks.append({"expr": optimized, "eval_time": "72h",
                           "exp_samples": [{"labels": output, "value": 614.2857142857143}]})
        elif case in ["not_full", "not_full_36h_ago", "missing_geo"]:
            checks.append({"expr": optimized, "eval_time": "72h", "exp_samples": []})
        tests.append({"name": f'{rule["uid"]}/{case}', "interval": "1h",
                      "input_series": inputs, "promql_expr_test": checks})

with tempfile.TemporaryDirectory() as temporary:
    path = Path(temporary) / "tests.json"
    path.write_text(json.dumps({"rule_files": [], "fuzzy_compare": True,
                               "evaluation_interval": "1h", "tests": tests}))
    subprocess.run([os.environ["PROMTOOL"], "test", "rules", str(path)], check=True)
print(f"Validated {len(rules)} retention queries across {len(tests)} cases")
PY
