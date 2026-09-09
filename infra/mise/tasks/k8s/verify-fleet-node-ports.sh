#!/usr/bin/env bash
#MISE description="Check the paths that must survive the fleet-node-ports-no-world host policy (kubectl logs/top on 10250, the overlay on 8472, cilium health on 4240) and diff the externally reachable port matrix on every node the policy selects."
#USAGE arg "<kube_context>" help="kubectl context for the cluster to check (e.g. tuist-k8s-production)"
#USAGE flag "--baseline" help="Record the port matrix instead of diffing it. Run once before deploying the policy."

# `fleet-node-ports-no-world` (infra/helm/platform/templates/
# fleet-node-ports-network-policy.yaml) denies `world` the kubelet, VXLAN and
# cilium-health ports on bare-metal fleet nodes. Its failure mode is silent: a
# node whose overlay is severed keeps reporting `Ready`, so every check here is
# a data path, not a node condition.
#
#   before the deploy:  mise -C infra run k8s:verify-fleet-node-ports <ctx> --baseline
#   after the deploy:   mise -C infra run k8s:verify-fleet-node-ports <ctx>
#
# The diff is the point: 10250 and 4240 must flip to closed on every selected
# node, 80/443 must not move, and anything else that changed is collateral.
# 8472/udp is not in the matrix because a UDP probe cannot distinguish a bound
# socket from a dropped packet; it is covered by the overlay checks instead.
#
# Needs one node per provider to be checkable, so run it against production for
# vultr coverage: staging and canary carry dedibox, scaleway and ovh only.

set -uo pipefail
CTX="${1:?usage: verify-fleet-node-ports <kube-context> [--baseline]}"
MODE="${2:-check}"
K="kubectl --context $CTX"
BASE="${TMPDIR:-/tmp}/fleet-node-ports-baseline-$CTX.txt"
PORTS=(22 80 443 4240 9962 10250)
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

mapfile -t NODES < <($K get nodes -l node.cluster.x-k8s.io/instance-type \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.node\.cluster\.x-k8s\.io/instance-type}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')

echo "== nodes the policy selects (${#NODES[@]}) =="
printf '  %s\n' "${NODES[@]}"

declare -A SEEN; TARGETS=()
for line in "${NODES[@]}"; do
  read -r name itype _ <<<"$line"
  [[ -n "${SEEN[$itype]:-}" ]] && continue
  SEEN[$itype]=1; TARGETS+=("$line")
done
echo "  one per provider: ${!SEEN[*]}"

echo
echo "== 10250: apiserver -> kubelet =="
for t in "${TARGETS[@]}"; do
  read -r name itype _ <<<"$t"
  read -r ns pn < <($K get pods -A --field-selector "spec.nodeName=$name,status.phase=Running" \
    -o jsonpath='{.items[0].metadata.namespace}{" "}{.items[0].metadata.name}' 2>/dev/null)
  if [[ -n "${pn:-}" ]] && $K -n "$ns" logs "$pn" --tail=1 --limit-bytes=512 --all-containers >/dev/null 2>&1; then
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

echo
echo "== 8472: overlay =="
for t in "${TARGETS[@]}"; do
  read -r name itype _ <<<"$t"
  total=$($K get pods -A --field-selector "spec.nodeName=$name" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  ready=$($K get pods -A --field-selector "spec.nodeName=$name" \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c True)
  if [[ "$ready" -gt 0 && "$ready" -eq "$total" ]]; then
    ok "$itype $ready/$total pods Ready (pod -> apiserver ClusterIP intact)"
  else
    bad "$itype $ready/$total pods Ready on $name"
  fi
done
# Cross-node reachability: an Endpoints object only lists addresses whose
# readiness probe passed, and the regional kura Services span boxes.
notready=$($K get endpointslices -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{range .endpoints[*]}{.conditions.ready}{","}{end}{"\n"}{end}' 2>/dev/null | grep -c 'false' || true)
printf '  INFO  endpointslices carrying a not-ready address: %s\n' "$notready"

echo
echo "== 4240: cilium agent health =="
for t in "${TARGETS[@]}"; do
  read -r name itype _ <<<"$t"
  r=$($K -n kube-system get pods -l k8s-app=cilium --field-selector "spec.nodeName=$name" \
      -o jsonpath='{range .items[*]}{.status.containerStatuses[*].restartCount}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null)
  if [[ "$r" == *True* ]]; then ok "$itype cilium agent Ready (restarts: ${r%% *})"; else bad "$itype cilium agent not Ready on $name"; fi
  cond=$($K get node "$name" -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type}{" "}{end}' 2>/dev/null)
  printf '  INFO  %s node conditions True: %s\n' "$itype" "$cond"
done

echo
echo "== port matrix from outside the cluster =="
matrix=""
for line in "${NODES[@]}"; do
  read -r name itype ip <<<"$line"
  [[ -z "${ip:-}" ]] && continue
  row="$ip"
  for p in "${PORTS[@]}"; do
    if nc -z -G 4 -w 4 "$ip" "$p" >/dev/null 2>&1; then row="$row $p:open"; else row="$row $p:closed"; fi
  done
  matrix="$matrix$row\n"
  printf '  %-16s %s  %s\n' "$itype" "$ip" "${row#* }"
done

if [[ "$MODE" == "--baseline" ]]; then
  printf "%b" "$matrix" > "$BASE"
  echo "  baseline written to $BASE"
elif [[ -f "$BASE" ]]; then
  echo
  echo "== diff against baseline =="
  d=$(diff <(cat "$BASE") <(printf "%b" "$matrix") || true)
  if [[ -z "$d" ]]; then
    bad "port matrix unchanged, the policy is not being enforced"
  else
    echo "$d" | sed 's/^/  /'
    closed3=$(printf "%b" "$matrix" | grep -c '10250:closed')
    open443=$(printf "%b" "$matrix" | grep -c '443:open')
    base443=$(grep -c '443:open' "$BASE")
    [[ "$closed3" -eq $(printf "%b" "$matrix" | grep -c .) ]] && ok "10250 closed on every selected node" || bad "10250 still open somewhere"
    [[ "$open443" -eq "$base443" ]] && ok "443 unchanged ($open443 nodes)" || bad "443 changed: $base443 -> $open443"
  fi
else
  echo "  (no baseline at $BASE; rerun with --baseline first)"
fi

echo
echo "== $pass passed, $fail failed =="
[[ "$fail" -eq 0 ]]
