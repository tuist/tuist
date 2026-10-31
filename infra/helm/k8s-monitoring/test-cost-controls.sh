#!/usr/bin/env bash
# Static validation does not compile stage.match LogQL. Start the exact shipped
# Alloy image with the rendered processing pipeline, without network access.
# ALLOY_BIN can instead point to the matching local release for local checks.
set -euo pipefail

directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary="$(mktemp -d)"
docker="${DOCKER:-docker}"
container="grafana-log-cost-controls-$$"
alloy_pid=""
cleanup_alloy() {
  if [[ -n "${alloy_pid}" ]]; then
    if [[ -n "${ALLOY_BIN:-}" ]]; then
      kill "${alloy_pid}" 2>/dev/null || true
    else
      "${docker}" rm -f "${container}" >/dev/null 2>&1 || true
    fi
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
printf '\nlogging { format = "json" }\nloki.echo "verification" {}\nloki.source.file "fixture" {\n  targets = [{"__path__" = "%s/fixture.log", "service_name" = "tuist", "container" = "server", "tmp_container_runtime" = "containerd"}, {"__path__" = "%s/ingress.log", "namespace" = "platform", "service_name" = "ingress-nginx", "container" = "controller", "tmp_container_runtime" = "containerd"}]\n  forward_to = [loki.process.pod_logs.receiver]\n}\n' "${temporary}" "${temporary}" >> "${temporary}/pipeline.alloy"

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
    print prefix "case_uid=operator_query_control method=GET status=200 atlas_operator_read_account_id=1 diagnostic=fixture?not_a_url=kept [info] Request completed"
    print prefix "case_uid=error_success [error] Embedded log: method=GET status=200 [info] Request completed"
    print prefix "case_uid=critical [critical] Embedded log: cache_outcome=miss method=GET status=404 [info] Request completed"
    print prefix "case_uid=warning [warning] Embedded log: cache_outcome=miss method=GET status=404 [info] Request completed"
    print prefix "case_uid=error [error] Embedded log: cache_outcome=miss method=GET status=404 [info] Request completed"
  }
  print prefix "case_uid=fixture_complete [info] Fixture complete"
}' > "${temporary}/fixture.log"

cat > "${temporary}/ingress.log" <<'EOF'
2026-10-29T00:00:00Z stdout F 192.0.2.1 - - [29/Oct/2026:00:00:00 +0000] "GET /live/websocket?_csrf_token=synthetic-query-secret&vsn=2.0.0 HTTP/1.1" 101 0 "https://synthetic.invalid/source?token=synthetic-referrer-secret" "test-agent" 500 1.5 [tuist-server-80] [] 192.0.2.2:4000 0 1.5 101 case_uid=ingress_websocket
2026-10-29T00:00:00Z stdout F 192.0.2.1 - - [29/Oct/2026:00:00:00 +0000] "POST /live/longpoll?%5Fcsrf_token=synthetic-query-secret&_csrf_token=second-synthetic-secret HTTP/1.1" 403 0 "-" "test-agent" 500 0.1 [tuist-server-80] [] 192.0.2.2:4000 0 0.1 403 case_uid=ingress_longpoll
2026-10-29T00:00:00Z stdout F 192.0.2.1 - - [29/Oct/2026:00:00:00 +0000] "GET /live/websocket?x=\x22&_csrf_token=synthetic-query-secret HTTP/1.1" 502 0 "-" "test-agent" 500 0.1 [tuist-server-80] [] 192.0.2.2:4000 0 0.1 502 case_uid=ingress_escaped_quote
2026-10-29T00:00:00Z stdout F 192.0.2.1 - - [29/Oct/2026:00:00:00 +0000] "GET /live/websocket HTTP/1.1" 101 0 "-" "test-agent, request: harmless" 500 1.5 [tuist-server-80] [] 192.0.2.2:4000 0 1.5 101 case_uid=ingress_agent_control
2026-10-29T00:00:00Z stderr F 2026/10/29 00:00:00 [error] 1#1: *1 case_uid=ingress_error connect() failed (111: Connection refused) while connecting to upstream, client: 192.0.2.1, request: "GET /live/websocket?_csrf_token=synthetic-query-secret HTTP/1.1", upstream: "http://192.0.2.2:4000/live/websocket?_csrf_token=synthetic-query-secret", referrer: "https://synthetic.invalid/source?token=synthetic-referrer-secret"
2026-10-29T00:00:00Z stderr F 2026/10/29 00:00:00 [error] 1#1: *2 case_uid=ingress_query_quote connect() failed (111: Connection refused) while connecting to upstream, client: 192.0.2.1, request: "GET /fail?x="&_csrf_token=synthetic-query-secret HTTP/1.1", referrer: "https://synthetic.invalid/?x="&_csrf_token=synthetic-referrer-secret"
2026-10-29T00:00:00Z stderr F 2026/10/29 00:00:00 [error] 1#1: *3 case_uid=ingress_value_quote connect() failed (111: Connection refused) while connecting to upstream, client: 192.0.2.1, request: "GET /fail?_csrf_token="synthetic-query-secret" HTTP/1.1"
2026-10-29T00:00:00Z stderr F 2026/10/29 00:00:00 [error] 1#1: *4 case_uid=ingress_truncated connect() failed (111: Connection refused) while connecting to upstream, client: 192.0.2.1, request: "GET /fail?_csrf_token="synthetic-query-secret
2026-10-29T00:00:00Z stderr F 2026/10/29 00:00:00 [error] 1#1: *5 case_uid=ingress_upstream_only connect() failed (111: Connection refused) while connecting to upstream, client: 192.0.2.1, upstream: "http://192.0.2.2:4000/fail?x="&_csrf_token=synthetic-query-secret"
2026-10-29T00:00:00Z stderr F 2026/10/29 00:00:00 [error] 1#1: *6 case_uid=ingress_referrer_only connect() failed (111: Connection refused) while connecting to upstream, client: 192.0.2.1, referrer: "https://synthetic.invalid/?x="&_csrf_token=synthetic-referrer-secret"
2026-10-29T00:00:00Z stdout F case_uid=ingress_complete
EOF

: > "${temporary}/alloy.log"
if [[ -n "${ALLOY_BIN:-}" ]]; then
  "${ALLOY_BIN}" run --disable-reporting --server.http.listen-addr=127.0.0.1:12345 --storage.path="${temporary}/alloy" \
    "${temporary}/pipeline.alloy" > "${temporary}/alloy.log" 2>&1 &
else
  if ! "${docker}" image inspect "${image}" >/dev/null 2>&1; then
    "${docker}" pull "${image}"
  fi
  "${docker}" run --rm --name "${container}" --network none \
    -v "${temporary}:${temporary}:ro" "${image}" \
    run --disable-reporting --storage.path=/tmp/alloy "${temporary}/pipeline.alloy" \
    > "${temporary}/alloy.log" 2>&1 &
fi
alloy_pid=$!
# The final unsampled record proves the tailer reached the protected cases,
# even when collector startup or fixture processing is slow on a CI runner.
deadline=$((SECONDS + 60))
until grep -q 'case_uid=fixture_complete ' "${temporary}/alloy.log" && \
  grep -q 'case_uid=ingress_complete' "${temporary}/alloy.log"; do
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
jq -Rr 'fromjson? | select(.receiver == "loki.echo.verification") | .entry' "${temporary}/alloy.log" > "${temporary}/retained.log"
for category in unexpected_404 forged_status forged_miss operator_read operator_grant operator_success_read operator_success_grant operator_query_control warning error error_success critical; do
  retained=$(grep -c "case_uid=${category} " "${temporary}/retained.log" || true)
  if [[ "${retained}" != 10 ]]; then
    printf 'Expected all 10 %s records, retained %s\n' "${category}" "${retained}" >&2
    awk '{ print }' "${temporary}/alloy.log" >&2
    exit 1
  fi
done
grep -q 'diagnostic=fixture?not_a_url=kept' "${temporary}/retained.log"
for category in websocket longpoll escaped_quote agent_control error query_quote value_quote truncated upstream_only referrer_only; do
  [[ $(grep -cE "case_uid=ingress_${category}( |$)" "${temporary}/retained.log") == 1 ]]
done
if grep -qE 'synthetic-query-secret|synthetic-referrer-secret|second-synthetic-secret' "${temporary}/retained.log"; then
  printf 'Ingress query credentials reached retained logs\n' >&2
  exit 1
fi
grep -Fq '"GET /live/websocket?[REDACTED] HTTP/1.1" 101' "${temporary}/retained.log"
grep -Fq '"POST /live/longpoll?[REDACTED] HTTP/1.1" 403' "${temporary}/retained.log"
[[ $(grep -Fc 'connect() failed (111: Connection refused) while connecting to upstream, client: 192.0.2.1' "${temporary}/retained.log") == 6 ]]
# A request-like user agent on stdout must not truncate access-log audit fields.
[[ $(grep -c ', request: harmless.*case_uid=ingress_agent_control$' "${temporary}/retained.log") == 1 ]]
[[ $(grep -cE ', (request|upstream|referrer): ' "${temporary}/retained.log") == 1 ]]
misses=$(grep -c 'case_uid=expected_miss ' "${temporary}/retained.log" || true)
successes=$(grep -c 'case_uid=routine_success ' "${temporary}/retained.log" || true)
if (( misses < 1 || misses > 500 || successes < 1 || successes > 2000 )); then
  printf 'Sampling failed: retained %s misses and %s successes out of 10,000 each\n' "${misses}" "${successes}" >&2
  exit 1
fi
printf 'Production log pipeline verified with %s: %s misses and %s successes retained; all protected records preserved\n' "${image}" "${misses}" "${successes}"
printf 'Ingress access queries redacted; error URL context removed, including quote/truncation bypasses; access audit fields and app audit records preserved\n'
