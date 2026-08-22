# egress-tree-agent

DaemonSet agent that enforces the kura per-tenant egress **floors**
(`egress_guaranteed_mbps`), **ceilings** (`egress_burst_mbps`), and the
node's **box cap** (`tuist.dev/egress-mbps` capacity) with one shared HTB
tree per node. It is the third egress layer for tuist/tuist#12363:

- The `kubernetes.io/egress-bandwidth` annotation (Cilium bandwidth manager)
  paces the NIC only and misses the node-local read path, and as a per-pod
  ceiling it can neither arbitrate between tenants (no floors) nor cap two
  replicas at 1×C.
- The HAProxy regional gateway (#12506 pilot) bounds the customer read leg
  at L7 on ca-east only.
- This agent is the kernel-level enforcement for all of it: work-conserving
  floors, per-tenant ceilings on every leg (node-local included), the
  cross-replica 1×C, and the box cap. There is deliberately **no pod-level
  qdisc underneath** (a per-pod shaper was prototyped as #12507 and dropped):
  it would add no cap this tree lacks, and — having no sibling awareness — it
  would throttle the node-local replica-sync traffic that this agent's
  sibling bypass exists to keep at line rate.

## Architecture: veth trampoline, not ifb

One veth pair per node, both ends in the host netns:

- `kura-egress0` carries the HTB tree as its root egress qdisc
  (`1:` htb `default 0` → root class `1:1` at the node budget → one class
  `1:<minor>` per tenant with an fq_codel leaf).
- `kura-egress1` is the return side.

Per kura pod, a tcx BPF program (`kura_shaper_out`) is attached to the
host-side veth (`lxc*`) **ingress** hook, anchored **first**, ahead of
Cilium's `cil_from_container`. It stamps `skb->priority` with the tenant
classid (HTB classifies by priority natively — the tree device needs no
filters), records the source ifindex in `skb->mark`, arms a `tc_index` loop
guard, and redirects into `kura-egress0`. After HTB pacing, the program on
`kura-egress1` (`kura_shaper_ret`) sends the packet back to the original
device's ingress hook (`BPF_F_INGRESS`); the loop guard disarms and falls
through to Cilium, which then applies policy/identity/forwarding exactly as
for an unshaped packet.

Lab findings (Cilium 1.18, TCX attach, BPF host routing, veth datapath) that
dictate this shape — do not regress them:

- **Legacy `tc` filters on `lxc*` ingress never run.** Cilium attaches via
  TCX and always returns a verdict, and the kernel runs the legacy clsact
  path only when no tcx program gave one. The design-doc form (`flower` +
  `matchall`/`mirred` filters) sees zero packets. Only a tcx program
  anchored before Cilium's can steal the packet.
- **The classic ifb detour voids network policy.** ifb re-injects with
  `tc_skip_classify`, the whole tcx hook is skipped, and shaped traffic
  re-enters through the host stack with the trusted host identity: measured
  bypass of both the source pod's egress NetworkPolicy and destination
  ingress NetworkPolicies. The trampoline re-entry has no skip flag, and
  both policy directions were re-verified enforced through it.
- **`skb->priority` does not survive the pod→host veth crossing** (the
  kernel scrubs it on every netns crossing), so the tenant tag cannot come
  from inside the pod. Stamping happens host-side, in the per-`lxc` program,
  from agent-supplied config. A side effect: the workload can never spoof
  its own class.
- **Cilium replaces its own tcx link in place** across endpoint regeneration
  and agent restarts and leaves foreign links alone; our pinned links keep
  their first position. The reconcile loop still verifies position every
  cycle and reattaches (plus a churn metric) if something strips them.
- Sibling traffic (headless DNS → the co-located replica's pod IP) takes a
  bypass branch before stamping and stays on Cilium's fast path
  (`redirect_peer`, measured at node-local line rate). The bypass is an
  explicit per-IP allowlist — fail-safe polarity: a stale entry briefly
  shapes sibling traffic, never unshapes tenant traffic.

## Contracts

- **Input:** the `tuist.dev/egress-class` pod annotation, rendered by
  kura-controller: `{"classid":"1:<hex>","floor_mbps":F,"burst_mbps":B}`.
  Annotation presence is the opt-in; the agent touches no other pods.
  Classid minors are allocated per account (stable, persisted on the
  KuraInstance as `kura.tuist.dev/egress-class-id`) by the controller — one
  component owns the id contract end-to-end.
- **Node budget:** `Node.status.capacity["tuist.dev/egress-mbps"]`
  (advertised by the CAPI provider, see
  `infra/cluster-api-provider-tuist/controllers/shared/node_egress.go`).
  Without it, `DEFAULT_NODE_EGRESS_MBPS` (observe mode) applies; with
  neither, the agent builds no tree and pods stay unshaped — it never
  invents a cap.
- **Device resolution:** the local Cilium agent's endpoint API over
  `/var/run/cilium/cilium.sock` (authoritative pod → `lxc*` mapping).
- **Reconcile model:** event-driven with a slow backstop (the same split
  Cilium's bandwidth manager uses). Field-selected pod/node informers kick a
  debounced converge (only shaped-pod events and egress-capacity changes
  trigger); a netlink link watch on the trampoline pair kicks the same
  trigger, because a deleted/downed trampoline drops shaped traffic and the
  informers cannot see it. `RECONCILE_INTERVAL` (default 2m) is the periodic
  sweep that repairs what no event reports — stripped tcx links, stale pins.
  A Running pod whose Cilium endpoint has not appeared yet, and a failed
  return-program attach, requeue a quick retry, so `skipped_pods` clears in
  seconds rather than flapping until the backstop.

## Fail-safe invariants (do not weaken)

- The return program is confirmed attached before any pod program is
  attached or kept. Without a return program, packets surfacing on
  `kura-egress1` are dropped (IPv4 forwarding is disabled on both trampoline
  ends), never forwarded around Cilium. Because already-attached pod
  programs keep redirecting into that drop, a failed return attach logs
  every attempt (error level), retries fast, and after
  `RETURN_ATTACH_MAX_FAILURES` consecutive failures (default 3) the agent
  detaches every pod program — unshaped beats blackholed.
- An unconfigured/partially configured pod program passes packets to Cilium
  unshaped rather than blackholing.
- With the agent absent or failing, pods run unshaped on the node-local leg
  (the NIC annotation still paces the wire leg). That fail-open trade is
  deliberate — shaping must never blackhole — so `skipped_pods`, attach
  errors, and DaemonSet health must alert.
- Shutdown performs no teardown: pinned links (under
  `/sys/fs/bpf/kura-egress-tree/`) keep enforcing across agent restarts and
  upgrades. Removing shaping is an explicit operator action: delete the
  DaemonSet, remove the pin directory, delete `kura-egress0`.
- `default 0` on the root qdisc: unclassified packets transmit unshaped via
  HTB's direct queue and increment a counter that must alert — every packet
  entering the tree was stamped, so a direct packet means a foreign redirect
  or a broken stamp.

## Known limitation

For shaped (redirected) packets, `cil_from_container` runs only at the
re-entry, i.e. all of Cilium's processing still happens exactly once — no
policy gap was measured (both directions verified in the lab). The gap that
*was* measured belongs to the rejected ifb design; if the trampoline is ever
replaced, re-run the policy bypass experiments first.

## Metrics / alerts

`:9469/metrics`. Alert on: `kura_egress_tree_direct_packets` growth,
`kura_egress_tree_return_dropped_packets` growth,
`kura_egress_tree_return_attach_failures_total` growth (a failing return
attach blackholes shaped pods until the detach threshold),
`kura_egress_tree_link_reattach_total` churn after steady state,
`kura_egress_tree_skipped_pods` > 0,
`kura_egress_tree_sibling_overflow_total` growth (an account outgrew the
16-entry sibling map; extra siblings run shaped instead of bypassed, with no
log — the counter is the only signal), and per-class floor violations under
contention (`kura_egress_tree_class_sent_bytes` rate vs the floor).

A pod-device convergence error keeps the last known-good program attached
(the device stays out of the stale sweep) and requeues a fast retry; a
transient sync hiccup never strips working enforcement.

One failure mode no `kura_egress_tree_*` counter can see: per-CPU softnet
backlog overflow. Each shaped packet takes two extra `enqueue_to_backlog`
trips (trampoline-peer receive, `BPF_F_INGRESS` re-inject), and overflow
beyond `netdev_max_backlog` is a silent kernel drop. Watch
`rate(node_softnet_dropped_total)` on shaped nodes (node-exporter's softnet
collector, already deployed fleet-wide) alongside the tripwires above.
Lab-measured headroom (k01, 24 cores, 1.4 KB UDP, 5-min sustained runs):
zero softnet and zero qdisc drops at 1.4M pkt/s aggregate across 50 shaped
pods and at 630k pkt/s from one pod; the single HTB root lock surfaced as
sender backpressure (~22% single-flow PPS cost vs unshaped), not as drops —
so `netdev_max_backlog` needs no tuning at these rates.

Ordering guarantee behind the direct-packet alarm: classes are upserted
before programs attach, and stale classes are pruned only after the stale
programs are detached — in neither direction does a program stamp a classid
that has no class. A hand-cleared root qdisc is the one gap: egress runs
fully unshaped until the backstop interval (default 2 m) rebuilds the tree
(the netlink watch covers link events, not qdisc state); `direct_packets`
growth is the signal.

## Development

- `go test ./...`, `go vet ./...` (linux; the tcx attach path needs a Linux
  kernel ≥ 6.6).
- BPF: `internal/agent/bpf/redirect.c`. The bpf2go bindings are NOT
  committed: run `go generate ./internal/agent` (needs clang + libbpf
  headers) before building or testing; the Dockerfile and the CI workflow
  both run it. Little-endian target only — the fleet has no big-endian
  machines.
- The program deliberately declares no `SEC("license")`: none of the
  helpers it calls is GPL-gated (verified: the kernel loads and attaches
  it license-free), which keeps the file under the repository's default
  license. If a future change adds a helper the verifier rejects with a
  GPL-restriction error, that helper needs a license discussion first,
  not a quiet `"GPL"` declaration.
- Image: `infra/egress-tree-agent/Dockerfile` (alpine + iproute2; the agent
  shells out to `ip`/`tc`), built by
  `.github/workflows/egress-tree-agent-image.yml` →
  `ghcr.io/tuist/egress-tree-agent`. Pin deployments by digest.
- Helm: `infra/helm/tuist/templates/egress-tree-agent.yaml`
  (`egressTreeAgent.*` values; privileged DaemonSet on the kura pools). Ships
  with a CiliumClusterwideNetworkPolicy `ingressDeny` rule dropping TCP
  `metricsPort` from `world` on those nodes: the listener binds the box's
  public IP (hostNetwork, no host firewall on the adopted bare metal), and
  the deny shape — unlike a host allow policy — cannot default-deny the
  node. In-cluster scrapes arrive as cluster identities and pass.

## Rollout state

Ships disabled (`egressTreeAgent.enabled: false`). Intended sequence:
observe mode on ca-east (generous ceilings, floors informational), validate
per-tenant counters, then real ceilings/floors per region.
`egressTreeAgent.betaPodPrefix` (`BETA_POD_PREFIX`) narrows attachment to
pods whose name starts with the prefix — the per-account beta gate for the
first enforcement step. Excluded pods stay unshaped and count in
`kura_egress_tree_beta_excluded_pods` (deliberately not in `skipped_pods`,
which alerts). Sibling allowlists are computed over all annotated pods, so a
matched pod keeps its bypass even when its co-located sibling is excluded;
prefix changes converge within one reconcile cycle in both directions. The per-replica
floor double-count in scheduler bin-packing must be fixed before floors go
live (known issue, separate change).
