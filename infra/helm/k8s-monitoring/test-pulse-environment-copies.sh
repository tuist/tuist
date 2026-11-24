#!/usr/bin/env bash
# Rules split across Pulse keep one copy per Pulse data source and, when other
# clusters still report to Grafana Cloud, the original on Cloud. Check that the
# copies run the same query, staging copies route as non-production, and the
# Cloud original is the production query with the Pulse clusters excluded, so
# no environment is evaluated twice or missed.
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

families=0
for source in "${directory}"/*-alert-rule*.json; do
  report="$(jq -c '
    "cluster!~\"tuist-production|tuist-staging|tuist-canary\"" as $exclusion
    | {"cg3i1jh2k1v5sb": "production", "pulse-metrics-staging": "staging", "pulse-metrics-canary": "canary"} as $pulse
    | def source: .data[0].datasourceUid;
      # Threshold conditions only mean their evaluator; Grafana fills the rest
      # with defaults that differ between API writes.
      def query: .data | map(del(.datasourceUid, .model.datasource)
        | if .model.conditions then .model.conditions |= map(.evaluator) else . end);
      def unexcluded: map(if .model.expr then .model.expr |=
        (split(", " + $exclusion) | join("") | split("{" + $exclusion + "}") | join("")) else . end);
    [if type == "array" then .[] else . end] | group_by(.title)[] | select(length > 1)
    | map(select($pulse[source])) as $copies
    | map(select($pulse[source] | not)) as $cloud
    | ($copies | map(select(source == "cg3i1jh2k1v5sb"))[0]) as $production
    | {
        title: .[0].title,
        ok: (($copies | map($pulse[source]) | sort) == ["canary", "production", "staging"]
          and ($copies | map([query, {condition, for, ruleGroup, folderUID, isPaused, labels: (.labels | del(.env))}]) | unique | length) == 1
          and all($copies[]; (.labels.env == "staging") == (source == "pulse-metrics-staging"))
          and ($cloud | length) <= 1
          and all($cloud[]; .data[0].datasourceUid == "grafanacloud-prom"
            and (query | unexcluded) == ($production | query)
            # Every label matcher block, so every selector, carries the exclusion.
            and all(.data[].model.expr // empty;
              (split("{") | length) == (split($exclusion) | length) and contains($exclusion))))
      }
  ' "${source}")"
  while IFS= read -r family; do
    [[ -n "${family}" ]] || continue
    families=$((families + 1))
    if [[ "$(jq -r .ok <<<"${family}")" != true ]]; then
      echo "$(basename "${source}"): $(jq -r .title <<<"${family}") is not split consistently" >&2
      exit 1
    fi
  done <<<"${report}"
done
[[ "${families}" -gt 0 ]]
echo "Checked ${families} rules split across Pulse environments"
