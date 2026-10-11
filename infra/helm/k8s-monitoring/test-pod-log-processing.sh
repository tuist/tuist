#!/usr/bin/env bash
# Run the rendered stages: alloy validate does not parse stage.match LogQL.
set -euo pipefail

chart="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for tool in helm yq jq alloy timeout; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done

# Use the production log shape, with distinguishable outcomes and asymmetric
# values so a filter for absent=0 cannot accidentally match absent=10.
jq -nc '
  {level: "INFO", message: "backfill pass started", target: "kura::backfill::pass", case: "started"},
  (range(1000) | {level: "INFO", message: "backfill pass completed", capacity_completed: false,
    absent: 0, target: "kura::backfill::pass", case: "routine"}),
  {level: "WARN", message: "backfill pass started", target: "kura::backfill::pass", case: "warning"},
  {level: "ERROR", message: "backfill pass completed", capacity_completed: false,
    absent: 0, target: "kura::backfill::pass", case: "error"},
  {level: "INFO", message: "backfill pass completed", capacity_completed: true,
    absent: 0, target: "kura::backfill::pass", case: "capacity"},
  {level: "INFO", message: "backfill pass completed", capacity_completed: false,
    absent: 10, target: "kura::backfill::pass", case: "absent"},
  {level: "INFO", message: "backfill pass started", target: "kura::other", case: "other_target"},
  {level: "INFO", message: "finished reading fixtures", case: "sentinel"}
' > "$work/input.log"

for environment in production canary staging; do
  helm template k8s-monitoring "$chart" -f "$chart/values-$environment.yaml" > "$work/rendered.yaml"
  yq -r 'select(.kind == "ConfigMap" and .metadata.name == "k8s-monitoring-alloy-logs") | .data."config.alloy"' \
    "$work/rendered.yaml" > "$work/rendered.alloy"

  # Keep every rendered pod-log stage; replace only discovery and the sink
  # with local files and console output so no cluster, credentials or Loki is needed.
  {
    echo 'logging { format = "json" }'
    echo 'loki.process "fixture" {'
    awk '
      /^  loki.process "pod_logs" \{/ { stages = 1; next }
      stages && /^    forward_to = argument.logs_destinations.value/ { exit }
      stages { print }
    ' "$work/rendered.alloy"
    echo '  forward_to = [loki.echo.fixture.receiver]'
    echo '}'
    echo 'loki.echo "fixture" {}'
    cat <<EOF
loki.source.file "fixture" {
  targets = [{__path__ = "$work/input.log", namespace = "kura", container = "kura", tmp_container_runtime = "fixture"}]
  forward_to = [loki.process.fixture.receiver]
}
EOF
  } > "$work/fixture.alloy"
  grep -q 'stage.match' "$work/fixture.alloy"
  alloy validate "$work/fixture.alloy"

  status=0
  timeout --signal=INT 5s alloy run --disable-reporting \
    --server.http.listen-addr=127.0.0.1:12345 --storage.path="$work/storage-$environment" \
    "$work/fixture.alloy" > "$work/output.log" 2>&1 || status=$?
  if [[ "$status" != 124 ]] || grep -q '"level":"error"' "$work/output.log"; then
    cat "$work/output.log" >&2
    echo "Pod log pipeline failed for $environment (exit $status)" >&2
    exit 1
  fi

  # Echo emits one JSON entry per line. Sampling is probabilistic; assert a
  # wide reduction bound, while important entries must survive exactly once.
  if ! jq -Rs -e '
    split("\n") | map(fromjson? | select(.receiver == "loki.echo.fixture") | .entry | fromjson | .case) as $cases
    | all(["warning", "error", "capacity", "absent", "other_target", "sentinel"][];
        . as $case | [$cases[] | select(. == $case)] | length == 1)
      and ([$cases[] | select(. == "started")] | length == 0)
      and ([$cases[] | select(. == "routine")] | length < 100)
  ' "$work/output.log" >/dev/null; then
    head -20 "$work/output.log" >&2
    echo "Unexpected pod log processing results for $environment" >&2
    exit 1
  fi
  echo "Pod log processing passed: $environment"
done
