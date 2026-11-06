#!/usr/bin/env bash
# Static validation does not compile stage.match LogQL. Start the exact shipped
# Alloy image with the rendered processing pipeline, without network access.
set -euo pipefail

directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
docker="${DOCKER:-docker}"
container="grafana-log-cost-controls-$$"
alloy_pid=""
cleanup_alloy() {
  if [[ -n "${alloy_pid}" ]]; then
    "${docker}" rm -f "${container}" >/dev/null 2>&1 || true
    wait "${alloy_pid}" || true
    alloy_pid=""
  fi
}
cleanup() {
  cleanup_alloy
  rm -rf "${temporary}"
}
trap cleanup EXIT
# v4.0.3's operator supplies this image when the Alloy CR omits it. Keep
# this in sync with the deployed collector, not a newer local Alloy binary.
image="${ALLOY_IMAGE:-grafana/alloy:v1.15.0}"

helm template k8s-monitoring "${directory}" -n observability \
  -f "${directory}/values-production.yaml" > "${temporary}/rendered.yaml"
yq ea -o=json '[.]' "${temporary}/rendered.yaml" | jq -r '
  .[] | select(.kind == "ConfigMap" and (.metadata.name | endswith("alloy-logs")))
  | .data["config.alloy"]
' > "${temporary}/logs.alloy"

awk '
  /^[[:space:]]*loki.process "pod_logs"/ {
    copying = 1
    indentation = substr($0, 1, index($0, "loki.process") - 1)
  }
  copying {
    if ($0 ~ /^[[:space:]]+forward_to = /) print "  forward_to = [loki.echo.verification.receiver]"
    else print
  }
  copying && $0 == indentation "}" { exit }
' "${temporary}/logs.alloy" > "${temporary}/pipeline.alloy"
test -s "${temporary}/pipeline.alloy"
printf '\nloki.echo "verification" {}\nloki.source.file "fixture" {\n  targets = [{"__path__" = "/fixture.log", "service_name" = "tuist", "container" = "server", "tmp_container_runtime" = "containerd"}]\n  forward_to = [loki.process.pod_logs.receiver]\n}\n' >> "${temporary}/pipeline.alloy"

awk 'BEGIN {
  prefix = "2026-10-14T00:00:00Z stdout F 00:00:00 "
  for (i = 0; i < 10000; i++) {
    print prefix "case_uid=expected_miss cache_outcome=miss method=GET status=404 [info] Request completed"
    print prefix "case_uid=routine_success method=GET status=200 [info] Request completed"
  }
  for (i = 0; i < 10; i++) {
    print prefix "case_uid=unexpected_404 method=GET status=404 [info] Request completed"
    print prefix "case_uid=forged_status path=/unexpected/status=200/foo method=GET status=404 [info] Request completed"
    print prefix "case_uid=forged_miss path=/unexpected/cache_outcome=miss method=GET status=404 [info] Request completed"
    print prefix "case_uid=operator_read cache_outcome=miss method=GET status=404 atlas_operator_read_account_id=1 [info] Request completed"
    print prefix "case_uid=operator_grant cache_outcome=miss method=GET status=404 operator_grant_jti=test [info] Request completed"
    print prefix "case_uid=operator_success_read method=GET status=200 atlas_operator_read_account_id=1 [info] Request completed"
    print prefix "case_uid=operator_success_grant method=GET status=200 operator_grant_jti=test [info] Request completed"
    print prefix "case_uid=error_success [error] Embedded log: method=GET status=200 [info] Request completed"
    print prefix "case_uid=critical [critical] Embedded log: cache_outcome=miss method=GET status=404 [info] Request completed"
    print prefix "case_uid=warning [warning] Embedded log: cache_outcome=miss method=GET status=404 [info] Request completed"
    print prefix "case_uid=error [error] Embedded log: cache_outcome=miss method=GET status=404 [info] Request completed"
  }
  print prefix "case_uid=fixture_complete [info] Fixture complete"
}' > "${temporary}/fixture.log"

if ! "${docker}" image inspect "${image}" >/dev/null 2>&1; then
  "${docker}" pull "${image}"
fi
"${docker}" run --rm --name "${container}" --network none \
  -v "${temporary}/pipeline.alloy:/config.alloy:ro" \
  -v "${temporary}/fixture.log:/fixture.log:ro" "${image}" \
  run --disable-reporting --storage.path=/tmp/alloy /config.alloy \
  > "${temporary}/alloy.log" 2>&1 &
alloy_pid=$!
# The final unsampled record proves the tailer reached the protected cases,
# even when collector startup or fixture processing is slow on a CI runner.
deadline=$((SECONDS + 60))
until grep -q 'case_uid=fixture_complete ' "${temporary}/alloy.log"; do
  if ! kill -0 "${alloy_pid}" 2>/dev/null || (( SECONDS >= deadline )); then
    printf 'Alloy did not finish processing the fixture\n' >&2
    awk '{ print }' "${temporary}/alloy.log" >&2
    exit 1
  fi
  sleep 0.5
done
cleanup_alloy
grep -q 'finished node evaluation' "${temporary}/alloy.log"
if grep -qE 'invalid stage config|invalid selector|could not perform the initial load' "${temporary}/alloy.log"; then
  awk '{ print }' "${temporary}/alloy.log" >&2
  exit 1
fi
for category in unexpected_404 forged_status forged_miss operator_read operator_grant operator_success_read operator_success_grant warning error error_success critical; do
  retained=$(grep -c "case_uid=${category} " "${temporary}/alloy.log" || true)
  if [[ "${retained}" != 10 ]]; then
    printf 'Expected all 10 %s records, retained %s\n' "${category}" "${retained}" >&2
    awk '{ print }' "${temporary}/alloy.log" >&2
    exit 1
  fi
done
misses=$(grep -c 'case_uid=expected_miss ' "${temporary}/alloy.log" || true)
successes=$(grep -c 'case_uid=routine_success ' "${temporary}/alloy.log" || true)
if (( misses < 1 || misses > 500 || successes < 1 || successes > 2000 )); then
  printf 'Sampling failed: retained %s misses and %s successes out of 10,000 each\n' "${misses}" "${successes}" >&2
  exit 1
fi
printf 'Production log pipeline verified with %s: %s misses and %s successes retained; all protected records preserved\n' "${image}" "${misses}" "${successes}"
