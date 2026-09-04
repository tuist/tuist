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
  Because Cilium leaves our links alone, a reattach means external
  interference, and the metric counts only that: a brand-new pod device has
  no pin yet and lands on `kura_egress_tree_link_attach_total` instead. The
  discriminator is pin existence, not `linkAttached`, which deliberately
  reads a present-but-unreadable pin as detached — that case is interference
  to report, not a pod that never had a program.
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
  The rates in it are the account's effective pair: the region's floor and
  ceiling unless staff set a per-account, per-region override on the ops account
  page, which the server renders into `spec.egressGuaranteedMbps` and the
  bandwidth pod annotation so the same numbers reach the scheduler's
  reservation, Cilium's pacing, and this class. Those are pod-spec state, so a
  retune arrives on freshly created pods; this agent sees the new annotation
  when the pod informer reports the replacement and converges within about a
  second of it.
- **Tenant identity (metrics only):** the `tuist.dev/account` pod label, set
  by kura-controller on every kura pod. A classid is stable for a live
  account but not unique over time — the controller frees a minor when an
  account's last instance goes and hands the same one to another account
  later — so a `classid`-only series splices two tenants together, and
  nothing account-level can be built from it without joining the CR
  annotation. Every `kura_egress_tree_class_*` series carries the handle
  beside the classid. Reading it changes no enforcement: the annotation
  remains the sole opt-in, and a pod without the label is shaped exactly the
  same, with an empty `account`.
  The agent trusts the classid-to-account mapping rather than policing it, and
  deliberately exports no conflict counter: the controller allocates a minor
  per account under one leader with one reconcile worker, and the probe reads
  every existing claim through `APIReader` (a quorum read, not the informer
  cache) before choosing, so that loop cannot give two accounts one minor.
  Anything that does produce a duplicate — a hand-edited
  `kura.tuist.dev/egress-class-id`, a KuraInstance outside the namespace the
  probe scans — is a broken invariant to fix at the controller, not a steady
  state for this agent to measure. A class that did change hands shows up as
  `old_account` on the `updated tenant class` log line.
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
  upgrades. Consequently `enabled: false` (or deleting the DaemonSet) stops
  shaping only for pods created afterwards; already-shaped pods stay shaped.
  Removing enforcement is an explicit operator action that must not depend
  on this agent running, and has a load-bearing order (pod pins, then the
  return pin, then `kura-egress0` — a pod program left attached to a deleted
  trampoline blackholes that pod). The procedure is the breakglass section
  of [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
- **The box cap binds the floor, not just the ceiling.** `classRates` clamps a
  tenant's floor to the node budget *before* raising its ceiling to meet that
  floor. Clamping only the ceiling leaves a hole: a floor larger than the whole
  budget (a mistyped override, a hand-edited CR) carries the ceiling with it past
  the cap this tree exists to hold — a 2000 Mbps floor on a 1000 Mbps box yields
  `rate 2Gbit ceil 2Gbit`. The root class cannot hand out what it does not have
  anyway.
- **tc validates none of this, so `classRates` is the only guard.** Measured on a
  live tree: two child classes at `rate 800mbit` under a `rate 1gbit` root both
  install with exit 0, and a single class with `rate 900mbit ceil 100mbit`
  installs cleanly. HTB does no admission control on the sum of child rates — it
  shares out in proportion under contention instead. Nothing in the kernel will
  say a floor is unkeepable or unreachable; that has to come from this agent's
  metrics and from the ops form.
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

`:9469/metrics`. Per-class series are labelled `{classid, account}` (see
Contracts) and carry, beside the byte and drop counters, HTB's own accounting
of where a class's traffic came from: `kura_egress_tree_class_lended_packets`
(sent within the class's own rate) and `..._borrowed_packets` (sent by taking
tokens from the root class), plus `..._rate_bytes_per_second` and
`..._ceil_bytes_per_second` read back from the kernel. The rates are read back
rather than taken from the desired class so they describe what HTB is
enforcing — clamps and hand edits included — and they are in bytes per second,
the unit `rate(kura_egress_tree_class_sent_bytes[…])` is already in, so demand
against the floor is one query with nothing to join:

```
rate(kura_egress_tree_class_sent_bytes[5m]) / kura_egress_tree_class_rate_bytes_per_second
rate(kura_egress_tree_class_borrowed_packets[5m])
  / rate(kura_egress_tree_class_lended_packets[5m])
```

A class sustaining either well above 1 wants a floor larger than it has; one
that never borrows is not using the floor it reserves. Both are per account,
which is what makes them usable for sizing an account's `/ops` override.

The ratio only says something about a class that has a floor. A tenant
without one runs on the 1 Mbit trickle `classRates` gives it, so it borrows
nearly everything by construction; for those, the demand input is
`rate(kura_egress_tree_class_sent_bytes[…])` per account on its own.

Every class gauge is refreshed once per reconcile, not per scrape (the agent
shells out to `tc`, which does not belong on the scrape path), so on a quiet
node the values are up to `RECONCILE_INTERVAL` (default 2m) old and a scrape
can repeat the previous value. Keep rate windows several multiples of that.

Alert on: `kura_egress_tree_direct_packets` growth,
`kura_egress_tree_return_dropped_packets` growth,
`kura_egress_tree_return_attach_failures_total` growth (a failing return
attach blackholes shaped pods until the detach threshold),
`kura_egress_tree_link_reattach_total` growth at all (see below),
`kura_egress_tree_skipped_pods` > 0,
`kura_egress_tree_sibling_overflow_total` growth (an account outgrew the
16-entry sibling map; extra siblings run shaped instead of bypassed, with no
log — the counter is the only signal), and per-class floor violations under
contention (`kura_egress_tree_class_sent_bytes` rate vs
`kura_egress_tree_class_rate_bytes_per_second`).

Do not alert on `kura_egress_tree_link_attach_total`. It counts first
attaches on new pod devices — one per pod creation — so it tracks pod churn,
not shaping integrity: a fleet-wide kura rollout replaces every pod, each
replacement gets a new `lxc` device, and the counter climbs by the node's
whole pod count with nothing wrong. It is there for rollout visibility and to
keep that traffic out of the reattach signal, which used to carry both and
tripped its alert on every kura release. `kura_egress_tree_link_reattach_total`
now moves only when a link we already installed was stripped or displaced, so
it should sit flat at zero and any growth is worth a look; the matching
`reattached pod program` warning names the pod and device. The production
alert still carries the old `> 5` per-hour threshold that was chosen to ride
over rollout noise; drop it to `> 0` once this split is deployed across the
fleet, and not before — until then the running agents still emit the
conflated counter and a tighter threshold only fires sooner on rollouts.

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
  shells out to `ip`/`tc`) → `ghcr.io/tuist/egress-tree-agent`.
  `.github/workflows/egress-tree-agent-image.yml` validates PRs and publishes
  `:sha-<git-sha>` for pre-release iteration.
- Release + deploy: same shape as the other independently-released infra
  components (runners-controller, stable-egress-controller). A push to main
  touching `infra/egress-tree-agent/**` makes `mise run release:check` bump
  the component (`mise/tasks/release/components.json` +
  `infra/egress-tree-agent/cliff.toml`, type-only parsers so `feat(infra):`
  counts); `server-production-deployment.yml`'s `release-egress-tree-agent`
  job builds `ghcr.io/tuist/egress-tree-agent:<semver>`, `tag-infra-releases`
  pushes `egress-tree-agent@<semver>` only once that image is confirmed
  published, and `server-deployment.yml` resolves the highest such tag
  reachable from the deployed commit into `egressTreeAgent.image.tag`. So
  there is no in-repo image pin to bump, and the DaemonSet rolls only when
  the agent itself changed — not on every server deploy. To run an unreleased
  build, dispatch `server-deployment.yml` with
  `egress_tree_agent_image_tag: sha-<git-sha>`.
- Helm: `infra/helm/tuist/templates/egress-tree-agent.yaml`
  (`egressTreeAgent.*` values; privileged DaemonSet on the kura pools). Ships
  with a CiliumClusterwideNetworkPolicy dropping TCP `metricsPort` from
  `world` on those nodes: the listener binds the box's public IP
  (hostNetwork, no host firewall on the adopted bare metal). The policy
  pairs the `ingressDeny` with a baseline allow-all ingress rule — ANY host
  policy selecting a node, deny rules included, switches the host endpoint
  into ingress enforcement (staging-verified: a deny-only version
  default-denied the kura nodes). In-cluster scrapes arrive as cluster
  identities and pass.

## Rollout state

Ships disabled (`egressTreeAgent.enabled: false`). Enabled on staging,
canary, and production, where it attaches to **every** annotated pod on the
listed pools. Staging has run ungated since the agent landed (#12525);
canary and production now match it, because the `BETA_POD_PREFIX` gate that
held their first enforcement step to `kura-tuist-*` pods (#12564) is gone,
and with it the `kura_egress_tree_beta_excluded_pods` gauge. The annotation
is the only opt-in left, so an account reaches the tree the moment
kura-controller renders `tuist.dev/egress-class` onto its pods. Newly matched pods attach
within one reconcile cycle; nothing detaches, so removing the gate only ever
widens enforcement.

Remaining sequencing: ceilings are live, floors stay informational until the
per-replica floor double-count in scheduler bin-packing is fixed (known
issue, separate change).
