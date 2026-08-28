# egress-tree-agent troubleshooting

Operator procedures for the per-node egress HTB tree. The architecture,
invariants, and alert signals are in [AGENTS.md](AGENTS.md); this file is
what to run when something is wrong.

## Breakglass: remove shaping from the kura nodes

Use this when the shaping is suspected of hurting traffic — throttled
tenants, `kura_egress_tree_direct_packets` or
`kura_egress_tree_return_dropped_packets` growing,
`node_softnet_dropped_total` climbing on the kura pools, a datapath
regression after an agent or Cilium upgrade — and you want the nodes back on
the plain Cilium path now, without depending on the agent working.

**Stopping the agent does not stop shaping.** The tcx links are bpffs-pinned
under `/sys/fs/bpf/kura-egress-tree/` and shutdown does no teardown, by
design (enforcement survives restarts and upgrades). After
`egressTreeAgent.enabled: false` or `kubectl delete ds`, every pod that was
already shaped stays shaped until that pod is deleted; only pods created
afterwards run unshaped. Step 2 below is what actually removes the
enforcement.

What is on a node and what removes it:

| State | Removed by |
|---|---|
| Per-pod tcx programs, pinned at `/sys/fs/bpf/kura-egress-tree/pods/<lxc*>/link` | unlinking the pin — the agent closes its FDs after pinning, so the pin is the last reference and `rm` detaches the program |
| Return program, pinned at `/sys/fs/bpf/kura-egress-tree/return/link` | same |
| `kura-egress0`/`kura-egress1` veth pair, the HTB tree, the per-device sysctls | `ip link del kura-egress0` (deleting one end removes its peer and everything attached) |

**The order is load-bearing.** A pod program that is still attached when
`kura-egress0` disappears keeps redirecting into a dead ifindex and that
pod's egress is dropped. Pod pins first, then the return pin, then the
device — never the other way around.

### 1. Stop the agent

The DaemonSet lives in the kura namespace (`kuraController.namespace`) on the
managed environments; a self-hosted release renders it into the release
namespace instead.

```bash
export KUBECONFIG=~/.kube/tuist-<env>.yaml   # cluster-admin kubeconfig, see infra/k8s/onboarding.md
# Capture the image first: step 2 reuses it because it is already pulled on
# every kura node and ships iproute2. Any alpine with iproute2 works too.
IMAGE=$(kubectl -n kura get ds tuist-tuist-egress-tree-agent -o jsonpath='{.spec.template.spec.containers[0].image}')
kubectl -n kura delete ds tuist-tuist-egress-tree-agent
```

The next `server-deployment.yml` run would re-create the DaemonSet, so open a
PR setting `egressTreeAgent.enabled: false` in
`infra/helm/tuist/values-managed-<env>.yaml` in parallel, and do not deploy
that env until it lands — a returning agent re-shapes every annotated pod
within seconds of starting.

### 2. Wipe the node state

One debug pod per node, on the pools the agent ran on
(`egressTreeAgent.nodePools` in the env's values file). `--profile=sysadmin`
makes the pod privileged, and node debug pods are host-network with the
host filesystem at `/host`, so the pinned links and the trampoline are
reachable directly.

Run it non-interactively (no `-it`): `kubectl exec`/`attach`/`logs` do not
work against the kura-fleet nodes (the apiserver cannot reach those
kubelets), so the result is read from the pod phase instead. The script
verifies its own work and exits non-zero if anything is left, which turns
into pod phase `Error` for that node.

```bash
POOLS='kura-dedibox,kura-us-east,kura-us-west,kura-ap-southeast'   # from values-managed-<env>.yaml
for node in $(kubectl get nodes -l "node.cluster.x-k8s.io/pool in ($POOLS)" -o jsonpath='{.items[*].metadata.name}'); do
  kubectl debug "node/$node" --image="$IMAGE" --profile=sysadmin -q -- sh -ec '
    PIN=/host/sys/fs/bpf/kura-egress-tree
    # 1. pod programs — before anything else (see the ordering note)
    rm -rf "$PIN/pods"
    # 2. return program
    rm -rf "$PIN"
    # 3. trampoline pair + HTB tree
    ip link del kura-egress0 2>/dev/null || true
    [ ! -e "$PIN" ]
    if ip link show kura-egress0 >/dev/null 2>&1; then echo "kura-egress0 still present" >&2; exit 1; fi
  '
done
```

A `NotReady` node in the pool keeps its debug pod `Pending`; skip it —
nothing is serving from there, and the pins go away with the next kubelet
restart's pod churn or a re-run of this step once it is back.

### 3. Verify and clean up

```bash
# Completed = node is clean; Error = that node needs a look
kubectl get pods -o wide | grep node-debugger-
kubectl get pods -o name | grep node-debugger- | xargs -r kubectl delete
```

In Grafana, the `kura_egress_tree_*` series stop (the exporter is gone) and
the tenant symptom that triggered this clears. The wire-leg pacing from the
`kubernetes.io/egress-bandwidth` annotation (Cilium bandwidth manager) still
applies; only the shared-tree floors, ceilings, and box cap are gone.

No kura pod needs restarting: once its program is detached, a pod's traffic
takes Cilium's normal path from the next packet on. Exercised on the k01 lab
(2026-08-28, two nodes, one tenant class plus a lab pod at `ceil 300mbit`):
the agent's removal alone left throughput at 284 Mbit/s; the wipe took 13 s
for both nodes, moved it to line rate, and a 4 Hz probe against a shaped
kura pod's `/up` saw no failure across it. Deleting `kura-egress0` before the
pins, on the same setup, blackholed the shaped pod until the pins were
removed — the ordering above is not theoretical.

### Re-enabling

Set `egressTreeAgent.enabled: true` and deploy. The agent rebuilds from zero
host state (trampoline, tree, pins) and re-attaches to every annotated pod
within a couple of seconds of starting; nothing from the wipe needs undoing.

### Narrower levers

- **One account.** `egressTreeAgent.betaPodPrefix` limits attachment to pods
  whose name starts with the prefix; excluded pods are detached and cleaned
  within one reconcile cycle. This needs a healthy agent and a deploy, so it
  is a rollout lever, not an incident one.
- **One node.** Run the step-2 debug pod against that node only, after
  deleting the agent DaemonSet — a running agent re-attaches within the
  backstop interval (`RECONCILE_INTERVAL`, default 2m).
