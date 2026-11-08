#!/usr/bin/env bash
#MISE description="Test connectivity capture privacy and failed-read handling without cluster access"
set -euo pipefail
umask 077
script_dir=$(dirname "$(realpath "$0")")
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin"
export PATH="$fixture/bin:$PATH"
export CAPTURE_CALLS="$fixture/calls"
cat > "$fixture/bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$CAPTURE_CALLS"
case " $* " in
  *' logs '*)
    if [[ ${CAPTURE_MODE:-} == failed ]]; then
      echo '2026-01-01T00:00:00Z {"event.name":"kura.telemetry.http_export_failed","error.type":"connect"}'
      echo 'SECRET_FIXTURE_VALUE' >&2
      exit 1
    fi
    if [[ " $* " == *' cilium-agent '* ]]; then
      echo '2026-01-01T00:00:02Z msg="Unable to contact k8s api-server" error="dial tcp: i/o timeout SECRET_FIXTURE_VALUE"'
    else
      echo '2026-01-01T00:00:01Z {"event.name":"kura.connectivity.sample","target":"tuist-tuist-server.tuist.svc.cluster.local","port":80,"outcome":"ok","total_ms":21,"payload":"SECRET_FIXTURE_VALUE"}'
      echo '2026-01-01T00:00:02Z {"fields":{"event.name":"kura.telemetry.http_export_failed","error.type":"connect","message":"SECRET_FIXTURE_VALUE","kura.telemetry.export.duration_ms":3000}}'
      echo '2026-01-01T00:00:03Z {"event.name":"kura.connectivity.sample","target":"SECRET_FIXTURE_VALUE","outcome":"ok"}'
      echo '2026-01-01T00:00:04Z {"message":"SECRET_FIXTURE_VALUE"}'
    fi ;;
  *' get pods '*)
    if [[ ${CAPTURE_MODE:-} == no-agent ]]; then
      echo '{"items":[]}'
    else
      echo '{"items":[{"metadata":{"name":"fixture-cilium","namespace":"kube-system","uid":"agent-uid"}}]}'
    fi ;;
  *' get pod '*)
    if [[ ${CAPTURE_MODE:-} == oversized ]]; then
      head -c 1100000 /dev/zero | tr '\0' ' '
    elif [[ ${CAPTURE_MODE:-} == malformed ]]; then
      echo 'invalid JSON SECRET_FIXTURE_VALUE'
    else
      echo '{"metadata":{"name":"fixture-pod","namespace":"kura","uid":"pod-uid","annotations":{"private":"SECRET_FIXTURE_VALUE"},"ownerReferences":[{"controller":true,"kind":"StatefulSet","name":"fixture-set"}]},"spec":{"nodeName":"fixture-node","containers":[{"env":[{"name":"PASSWORD","value":"SECRET_FIXTURE_VALUE"}]}]},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True","message":"SECRET_FIXTURE_VALUE"}],"containerStatuses":[{"name":"kura","imageID":"sha256:fixture","restartCount":0,"ready":true}]}}'
    fi ;;
  *' get statefulset '*) echo '{"metadata":{"name":"fixture-set","generation":2},"status":{"observedGeneration":2,"replicas":2,"readyReplicas":2,"currentRevision":"old","updateRevision":"new"}}' ;;
  *' get node '*) echo '{"metadata":{"name":"fixture-node","uid":"node-uid"},"status":{"conditions":[{"type":"Ready","status":"True","message":"SECRET_FIXTURE_VALUE"}]}}' ;;
  *) echo 'Forbidden operation in read-only capture' >&2; exit 99 ;;
esac
MOCK
chmod +x "$fixture/bin/kubectl"

for mode in normal failed oversized malformed no-agent; do
  mkdir "$fixture/$mode"
  if CAPTURE_MODE=$mode bash "$script_dir/capture-connectivity.sh" tuist-k8s-production kura \
    2026-01-01T00:00:00Z "$fixture/$mode" fixture-pod > "$fixture/$mode-console" 2>&1; then
    [[ "$mode" == normal ]] || { echo "Accepted failed $mode capture" >&2; exit 1; }
  else
    [[ "$mode" != normal ]] || { cat "$fixture/$mode-console" >&2; exit 1; }
  fi
  output=$(echo "$fixture/$mode"/connectivity-capture.*)
  if rg -q 'SECRET_FIXTURE_VALUE|PASSWORD|payload' "$output" "$fixture/$mode-console"; then
    echo "Private content escaped the projection" >&2
    exit 1
  fi
  if [[ "$mode" == normal ]]; then
    [[ ! -e "$output/INCOMPLETE" ]]
    jq -e '.uid == "pod-uid" and .ready == "True" and .containers[0].restartCount == 0' "$output/pod-1.json" >/dev/null
    jq -se 'length == 2 and .[0].event == "sample" and .[0].total_ms == 21 and .[1].category == "connect"' "$output/pod-1-logs.jsonl" >/dev/null
    jq -se 'length == 1 and .[0].event == "cilium_api_timeout"' "$output/cilium-1-logs.jsonl" >/dev/null
  else
    [[ -e "$output/INCOMPLETE" && -s "$output/unavailable.txt" ]]
    if [[ "$mode" == failed ]]; then [[ ! -e "$output/pod-1-logs.jsonl" ]]; fi
  fi
done
if rg -q ' (exec|debug|proxy|patch|apply|delete|secrets) ' "$CAPTURE_CALLS"; then
  echo "Capture attempted a non-view operation" >&2
  exit 1
fi
[[ -z $(find "$fixture/normal" -perm -004 -type f -print) ]]
echo 'Connectivity capture privacy and failed-read checks passed.'
