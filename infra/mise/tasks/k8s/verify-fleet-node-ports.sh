#!/usr/bin/env bash
#MISE description="Check that the fleet-node-ports-no-world host policy closed the three ports to the internet and broke nothing inside the cluster: an in-cluster probe Job for the overlay and node-to-node paths, plus a full external port-matrix diff on every node the policy selects."
#USAGE arg "<kube_context>" help="kubectl context for the cluster to check (e.g. tuist-k8s-production)"
#USAGE flag "--baseline" help="Record the port matrix instead of diffing it. Run once before deploying the policy."

# `fleet-node-ports-no-world` (infra/helm/platform/templates/
# fleet-node-ports-network-policy.yaml) denies `world` the kubelet (10250/tcp),
# VXLAN (8472/udp) and cilium-health (4240/tcp) ports on bare-metal fleet nodes.
#
#   before the deploy:  mise -C infra run k8s:verify-fleet-node-ports <ctx> --baseline
#   after the deploy:   mise -C infra run k8s:verify-fleet-node-ports <ctx>
#
# The two halves prove opposite directions, and neither alone is enough:
#
#   - The external port matrix, probed from wherever this runs, proves `world`
#     is denied. It compares every node against every port, so a port that was
#     not meant to move shows up as a failure rather than as silence.
#   - The probe Job proves everything that is not `world` still works. It runs
#     on a selected node and sends real packets: to a pod IP on a different
#     selected node (VXLAN), to a peer node's 4240, and to the apiserver
#     ClusterIP, which is the path that died silently when ufw shipped enabled
#     on the Vultr image. Its verdict is read back through `kubectl logs`, so it
#     needs no exec.
#
# Node readiness and pod readiness are not used as evidence for either. A node
# whose pod network is severed keeps reporting `Ready`, kubelet probes are
# local, and a Kura pod stays healthy after losing its peers.
#
# Checks that cannot run report SKIP, never PASS. Exit codes keep unproven
# distinct from verified, so neither a human nor a pipeline reads one as the
# other:
#
#   0  everything it checked passed, and it checked everything
#   1  a check failed
#   2  usage, discovery or baseline error, nothing was checked
#   3  nothing failed, but something could not be checked
#
# The probe Job needs create permission in the probe namespace, which the
# read-only kubectl tier does not have, so on canary and production it wants an
# elevated session. The two Grafana checks need PROM_URL, GRAFANA_USER and
# GRAFANA_TOKEN.
#
# 8472/udp is absent from the external matrix on purpose: a UDP probe cannot
# tell a bound socket from a dropped packet. Its evidence is the probe Job.
#
# Run it against production for vultr coverage; staging and canary carry
# dedibox, scaleway and ovh only.
set -uo pipefail

CTX="${1:?usage: verify-fleet-node-ports <kube-context> [--baseline]}"
MODE="${2:-check}"
K="kubectl --context $CTX"
BASE="${TMPDIR:-/tmp}/fleet-node-ports-baseline-$CTX.txt"
PROBE_NS="${FLEET_PROBE_NAMESPACE:-default}"
PROBE_IMAGE="public.ecr.aws/docker/library/busybox:1.37"
# Ports the policy is expected to close, and the value each must hold after it
# lands. Everything else in the matrix must come back unchanged.
declare -A EXPECTED_CHANGE=([10250]=closed [4240]=closed)
PORTS=(22 80 443 4240 9962 9965 10250)

pass=0; fail=0; skipped=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
skip() { printf '  SKIP  %s\n' "$1"; skipped=$((skipped+1)); }
die()  { printf 'ERROR: %s\n' "$1" >&2; exit 2; }

case "$MODE" in
  check|--baseline) ;;
  *) die "unknown mode '$MODE' (expected --baseline or nothing)" ;;
esac

# ---------------------------------------------------------------- discovery --
# An unchecked jsonpath read behind a pipe turns an auth or API failure into an
# empty node list, which then passes every check by having nothing to check.
if ! NODES_RAW=$($K get nodes -l node.cluster.x-k8s.io/instance-type \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.node\.cluster\.x-k8s\.io/instance-type}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>&1); then
  die "node discovery failed against context '$CTX': $NODES_RAW"
fi

NODES=()
while IFS= read -r line; do
  [[ -z "${line// }" ]] && continue
  NODES+=("$line")
done <<<"$NODES_RAW"

(( ${#NODES[@]} )) || die "the policy's nodeSelector matched no nodes in '$CTX'. Either the label node.cluster.x-k8s.io/instance-type is gone from the fleet, or this context has no bare-metal fleet."

if [[ "$MODE" == "check" && ! -f "$BASE" ]]; then
  die "no baseline at $BASE. Run with --baseline before deploying the policy; without it there is nothing to compare and a clean-looking run proves nothing."
fi

echo "== nodes the policy selects (${#NODES[@]}) =="
declare -A SEEN; TARGETS=()
for line in "${NODES[@]}"; do
  read -r name itype ip <<<"$line"
  [[ -n "$ip" ]] || die "node $name matches the selector but has no InternalIP; the port matrix would silently skip it"
  printf '  %-12s %-16s %s\n' "$itype" "$ip" "$name"
  [[ -n "${SEEN[$itype]:-}" ]] && continue
  SEEN[$itype]=1; TARGETS+=("$line")
done
echo "  one node per provider will be probed: ${!SEEN[*]}"

# --------------------------------------------- 10250: apiserver -> kubelet --
# Both of these traverse the port under test: kubectl logs is the apiserver
# dialing the kubelet, kubectl top is metrics-server doing the same.
echo
echo "== 10250: apiserver -> kubelet =="
for t in "${TARGETS[@]}"; do
  read -r name itype _ <<<"$t"
  read -r ns pn < <($K get pods -A --field-selector "spec.nodeName=$name,status.phase=Running" \
    -o jsonpath='{.items[0].metadata.namespace}{" "}{.items[0].metadata.name}' 2>/dev/null)
  if [[ -z "${pn:-}" ]]; then
    skip "$itype kubectl logs, no running pod on $name to read"
  elif $K -n "$ns" logs "$pn" --tail=1 --limit-bytes=512 --all-containers >/dev/null 2>&1; then
    ok "$itype kubectl logs"
  else
    bad "$itype kubectl logs ($name)"
  fi
  if $K top node "$name" --no-headers 2>/dev/null | grep -q '[0-9]%'; then
    ok "$itype kubectl top node"
  else
    bad "$itype kubectl top node ($name), metrics-server cannot reach the kubelet"
  fi
done

# ------------------------------- 8472 / 4240 / ClusterIP: in-cluster probes --
echo
echo "== in-cluster probes: overlay, peer 4240, apiserver ClusterIP =="

APISERVER_IP=$($K get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
PROBE_JOB="fleet-node-ports-probe-$RANDOM"
cleanup() { $K -n "$PROBE_NS" delete job "$PROBE_JOB" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }

render_probe() {
  local node="$1" target_ip="$2" target_port="$3" peer_ip="$4"
  cat <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: $PROBE_JOB
  namespace: $PROBE_NS
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: Never
      nodeName: $node
      tolerations:
        - operator: Exists
      containers:
        - name: probe
          image: $PROBE_IMAGE
          command: ["/bin/sh", "-c"]
          args:
            - |
              rc=0
              probe() {
                if nc -z -w 5 "\$2" "\$3" 2>/dev/null; then
                  echo "RESULT \$1 ok (\$2:\$3)"
                else
                  echo "RESULT \$1 FAILED (\$2:\$3)"
                  rc=1
                fi
              }
              probe overlay-pod-to-pod $target_ip $target_port
              probe peer-node-4240 $peer_ip 4240
              probe apiserver-clusterip ${APISERVER_IP:-none} 443
              exit \$rc
YAML
}

run_probe() {
  local from_node="$1" from_type="$2" peer_ip="$3" target_ip="$4" target_port="$5"
  local manifest; manifest=$(render_probe "$from_node" "$target_ip" "$target_port" "$peer_ip")

  # `auth can-i` answers from RBAC the gateway may not be enforcing, so ask the
  # API to admit the real object instead.
  local dry; dry=$(printf '%s' "$manifest" | $K apply --dry-run=server -f - 2>&1)
  if [[ $? -ne 0 ]]; then
    skip "$from_type in-cluster probes, cannot create a Job in $PROBE_NS: ${dry##*: }"
    return
  fi

  trap cleanup EXIT
  if ! printf '%s' "$manifest" | $K apply -f - >/dev/null 2>&1; then
    skip "$from_type in-cluster probes, Job create was refused"
    return
  fi

  local state="" i
  for ((i = 0; i < 60; i++)); do
    state=$($K -n "$PROBE_NS" get job "$PROBE_JOB" \
      -o jsonpath='{.status.conditions[?(@.status=="True")].type}' 2>/dev/null)
    [[ -n "$state" ]] && break
    sleep 2
  done

  local logs; logs=$($K -n "$PROBE_NS" logs "job/$PROBE_JOB" --tail=20 2>/dev/null)
  cleanup; trap - EXIT

  if [[ -z "$logs" ]]; then
    bad "$from_type in-cluster probes produced no output (job state: ${state:-timed out})"
    return
  fi
  while IFS= read -r line; do
    case "$line" in
      "RESULT "*" ok "*)     ok  "$from_type ${line#RESULT }" ;;
      "RESULT "*" FAILED "*) bad "$from_type ${line#RESULT }" ;;
    esac
  done <<<"$logs"
}

if [[ -z "$APISERVER_IP" ]]; then
  skip "in-cluster probes, could not read the kubernetes Service ClusterIP"
elif (( ${#NODES[@]} < 2 )); then
  skip "in-cluster probes, need at least two selected nodes to cross one"
else
  for t in "${TARGETS[@]}"; do
    read -r from_node from_type _ <<<"$t"
    # Target a pod on a DIFFERENT selected node, so the packet is encapsulated.
    # alloy-logs is a DaemonSet with a pod IP and a declared port on every node.
    peer="" ; peer_ip="" ; target_ip="" ; target_port=""
    for other in "${NODES[@]}"; do
      read -r oname _ oip <<<"$other"
      [[ "$oname" == "$from_node" ]] && continue
      # A hostNetwork pod reports podIP == hostIP, and its port would be a
      # node port rather than an overlay one. jsonpath cannot filter on the
      # absent hostNetwork field, so compare the two addresses here.
      read -r target_ip target_port < <($K get pods -A \
        --field-selector "spec.nodeName=$oname,status.phase=Running" \
        -o jsonpath='{range .items[*]}{.status.podIP}{" "}{.status.hostIP}{" "}{.spec.containers[0].ports[0].containerPort}{"\n"}{end}' 2>/dev/null \
        | awk 'NF==3 && $1 != $2 && $1 ~ /^[0-9.]+$/ && $3 ~ /^[0-9]+$/ {print $1, $3; exit}')
      if [[ -n "$target_ip" && -n "$target_port" ]]; then peer="$oname"; peer_ip="$oip"; break; fi
    done
    if [[ -z "$target_ip" ]]; then
      skip "$from_type in-cluster probes, no routable pod found on another selected node"
      continue
    fi
    printf '  ....  %s probing from %s to %s\n' "$from_type" "$from_node" "$peer"
    run_probe "$from_node" "$from_type" "$peer_ip" "$target_ip" "$target_port"
  done
fi

# ------------------------------------------- 4240: the cilium-health verdict --
# Only the cilium agent can test host -> peer-host 4240; no pod sees that path.
# Its verdict is cilium_unreachable_nodes, which must stay at zero. Adaptive
# Metrics has aggregated the cluster and pod labels off this series, so the
# query spans environments and answers "did any node lose a peer", not which.
echo
echo "== 4240: cilium-health verdict =="
HEALTH_QUERY='max(cilium_unreachable_nodes)'
if [[ -n "${PROM_URL:-}" && -n "${GRAFANA_USER:-}" && -n "${GRAFANA_TOKEN:-}" ]]; then
  v=$(curl -sf -u "$GRAFANA_USER:$GRAFANA_TOKEN" --get "$PROM_URL/api/v1/query" \
      --data-urlencode "query=$HEALTH_QUERY" 2>/dev/null \
      | sed -n 's/.*"value":\[[^,]*,"\([^"]*\)".*/\1/p')
  if [[ -z "$v" ]]; then
    bad "cilium_unreachable_nodes query returned nothing"
  elif [[ "$v" == "0" ]]; then
    ok "cilium_unreachable_nodes = 0"
  else
    bad "cilium_unreachable_nodes = $v, a node cannot reach a peer on 4240"
  fi
else
  skip "cilium-health verdict, set PROM_URL/GRAFANA_USER/GRAFANA_TOKEN. Query: $HEALTH_QUERY"
fi

# --------------------------------------------------------- policy-denied drops --
echo
echo "== policy-denied drops =="
# The `or on()` arm is a positive control: it makes a healthy cluster answer 0
# rather than an empty vector, so an empty answer can only mean the series is
# not being scraped and is a failure rather than a silent pass.
DROP_QUERY='sum(rate(hubble_drop_total{reason="POLICY_DENIED"}[15m])) or on() (0 * sum(rate(hubble_drop_total[15m])))'
if [[ -n "${PROM_URL:-}" && -n "${GRAFANA_USER:-}" && -n "${GRAFANA_TOKEN:-}" ]]; then
  v=$(curl -sf -u "$GRAFANA_USER:$GRAFANA_TOKEN" --get "$PROM_URL/api/v1/query" \
      --data-urlencode "query=$DROP_QUERY" 2>/dev/null \
      | sed -n 's/.*"value":\[[^,]*,"\([^"]*\)".*/\1/p')
  if [[ -z "$v" ]]; then
    bad "hubble_drop_total is not being scraped, so drops cannot be ruled out"
  elif [[ "$v" == "0" ]]; then
    ok "no POLICY_DENIED drops"
  else
    bad "POLICY_DENIED drops at $v/s, the deny is catching traffic it should not"
  fi
else
  skip "policy-denied drops, set PROM_URL/GRAFANA_USER/GRAFANA_TOKEN. Query: $DROP_QUERY"
fi

# ------------------------------------------------------------- port matrix --
echo
echo "== external port matrix =="
declare -A OBSERVED
for line in "${NODES[@]}"; do
  read -r name itype ip <<<"$line"
  row=""
  for p in "${PORTS[@]}"; do
    if nc -z -G 4 -w 4 "$ip" "$p" >/dev/null 2>&1; then s=open; else s=closed; fi
    OBSERVED["$ip:$p"]=$s
    row="$row $p:$s"
  done
  printf '  %-12s %-16s %s\n' "$itype" "$ip" "${row# }"
done

if [[ "$MODE" == "--baseline" ]]; then
  : > "$BASE"
  for line in "${NODES[@]}"; do
    read -r _ _ ip <<<"$line"
    for p in "${PORTS[@]}"; do printf '%s %s %s\n' "$ip" "$p" "${OBSERVED["$ip:$p"]}" >> "$BASE"; done
  done
  echo "  baseline written to $BASE"
  echo
  echo "== $pass passed, $fail failed, $skipped skipped =="
  (( fail == 0 )) || exit 1
  (( skipped == 0 )) || exit 3
  exit 0
fi

# Every node and every port is compared. A port named in EXPECTED_CHANGE must
# hold its expected value; every other port must match the baseline exactly.
echo
echo "== diff against baseline =="
compared=0
while read -r ip p was; do
  now="${OBSERVED["$ip:$p"]:-}"
  compared=$((compared + 1))
  if [[ -z "$now" ]]; then
    bad "$ip:$p was in the baseline but this run did not probe it (node gone from the selector?)"
    continue
  fi
  want="${EXPECTED_CHANGE[$p]:-$was}"
  if [[ "$now" == "$want" ]]; then
    [[ -n "${EXPECTED_CHANGE[$p]:-}" ]] && ok "$ip:$p $was -> $now"
  else
    bad "$ip:$p is $now, expected $want (baseline $was)"
  fi
done < "$BASE"

for line in "${NODES[@]}"; do
  read -r _ _ ip <<<"$line"
  grep -q "^$ip " "$BASE" || bad "$ip is selected now but absent from the baseline; re-baseline before trusting this diff"
done

(( compared > 0 )) || bad "baseline at $BASE is empty"

echo
echo "== $pass passed, $fail failed, $skipped skipped =="
if (( fail > 0 )); then exit 1; fi
if (( skipped > 0 )); then
  echo "   $skipped check(s) could not run. They are unproven, not passed; this is exit 3, not a clean run."
  exit 3
fi
exit 0
