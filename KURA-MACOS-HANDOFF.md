# Handoff: Kura runner-cache for the Scaleway macOS fleet

Status as of 2026-06-12 (PN/NodePort session). Branch
`feat/kura-macos-runner-cache` (worktree
`~/Developer/tuist/.claude/worktrees/kura-macos-runner-cache`), built on
merged PR #10982. All commits pushed. No PR opened yet.

## Goal

macOS Tart runner VMs on the Scaleway Mac mini fleet consume per-account
kura cache pods on a co-located Scaleway node pool (`kura-scw-fr-par`),
with VM→cache traffic on a Scaleway Private Network — NOT the tailnet,
NOT the WAN.

## Decisions locked with Marek (2026-06-12)

- Data plane: **Private Network + NodePort**, not tailnet, not
  node-as-router. Decisive facts: M4-M minis (fleet moves to M4 asap)
  get **10 Gb/s on the PN included** vs 1 Gb/s public default; Cilium
  `bpf-lb-external-clusterip=false` makes node-as-router need a
  cluster-wide flag AND it caps the fleet at one node's NIC. NodePort +
  `externalTrafficPolicy: Local` scales out per node.
- Instance-side PN bandwidth = rated bandwidth, **separate budget** from
  public (vxlan/control never competes with cache traffic). Source:
  Scaleway VPC FAQ + Apple silicon datasheet.
- Staging node: PRO2-S (€163/mo). Prod outline: 2× POP2-HC-16C-32G
  (€311 each, 3.2 Gb/s PN each), scale out not up (flat ~€97/Gbps),
  POP2-HM if miss-rate (RAM) dominates instead.
- Per-account egress cap via Cilium bandwidth manager (already enabled
  cluster-wide): staging 750M on the region spec. Cap ≈ NIC/2 policy.
- Volumes: per-account SBS (5K staging / 15K prod planned); IOPS
  isolation is per-volume by construction.
- Raising kura pod memory limit (cgroup v2 charges page cache to the
  pod; 2Gi default caps each tenant's warm set) — prod follow-up knob.

## What shipped this session (commits 94424f24fe, 8ec056e7c3)

- 94424f24fe: scw-fr-par-runners added to staging region list, hetzner
  flipped linux-only, tailscale Connector proxyClass pin (now likely
  DEAD for the cache path — NodePort doesn't use the subnet router;
  decide keep/drop at PR time).
- 8ec056e7c3 (the big one): NodePort data plane end to end.
  - kura-controller: `exposeNodePort` (creates `<instance>-external`
    NodePort Service pinned to primary pod, ETP Local, NodePorts
    preserved across reconciles), `clientCIDRs` (NetworkPolicy ipBlock
    — NodePort clients match no namespaceSelector), `podAnnotations`
    (egress cap passthrough). Status: `nodeAddress` (from node label
    `tuist.dev/pn-ipv4`) + `nodePortHTTP/GRPC`. RBAC + CRD updated.
  - server: region spec `data_plane: :node_port` + `client_cidrs` +
    `pod_annotations` on scw-fr-par-runners;
    `KubernetesController.external_endpoint/2`; activation waits on
    `:node_port_endpoint_not_ready`; `Kura.refresh_private_server_url/1`
    re-stamps `Server.url` every converged reconciler tick (pod moves
    node → URL follows). Dispatch untouched (reads `Server.url`).
  - infra: scaleway-csi values + ExternalSecret under
    `infra/k8s/mgmt/bootstrap/`; hcloud-csi node plugin excludes the
    `kura-scw-fr-par` pool.

## Live staging infra (created this session)

- PN `kura-runner-cache` 172.16.0.0/22, staging project, VPC
  `c3a31741…`, PN id `8c9cf4c1-74f0-4303-9061-fa9d9591e7b8`.
- PRO2-S `tuist-staging-kura-scw-fr-par-1`, instance id
  `dd93b962-cd10-40fc-a20d-2d18c1628bbf`, public 51.15.216.34, PN
  172.16.0.2. **Joined to staging cluster as node `51.15.216.34`**
  (kubeadm join via cloud-init; containerd 2.2.3; labels
  `node.cluster.x-k8s.io/pool=kura-scw-fr-par`,
  `tuist.dev/pn-ipv4=172.16.0.2`; providerID
  `scaleway://instance/fr-par-1/<id>` so hcloud CCM doesn't reap it).
  - GOTCHA: apiserver `--kubelet-preferred-address-types` has NO
    InternalIP (ExternalIP,Hostname,…) — node is therefore NAMED by its
    public IP so Hostname resolves; durable fix = add InternalIP to the
    flag via ClusterClass (CP rollout, all envs — follow-up).
  - Cilium KPR picked up BOTH NICs (ens2 public + ens6 PN) → NodePort
    IS served on the PN address. Verified via cilium status.
  - Cross-provider path verified: pod on scw node → kura pod on
    Hetzner via ClusterIP DNS = 200 in 0.25s.
- scaleway-csi installed (kube-system), `scw-bssd` StorageClass, creds
  ExternalSecret synced from SCALEWAY_API 1P item. Node plugin needed
  a MANUAL `kubectl patch ds scaleway-csi-node` for
  hostNetwork+ClusterFirstWithHostNet (chart has no knob; re-patch
  after any chart upgrade, or upstream a PR).
- Runners-fleet mini (`d8d8a91d…`): VPC enabled (no reboot needed!),
  attached to PN, **VLAN 2319**, IPAM gave it 172.16.0.3. macOS-side
  VLAN interface NOT configured yet (blocked, below).
- Image builds dispatched from branch tip 8ec056e7c3:
  kura-controller-image.yml + server-deployment.yml (build job only —
  background watcher cancels before the deploy job; sharp edge:
  CI staging deploys resolve controller images from git tags → crashloop).

## E2E state (2026-06-12 afternoon — everything unblocked and validated)

- IAM policy `tuist-staging-kura-csi-policy` created → PVC bound, SBS
  volume mounted and written. Test resources cleaned up.
- Mini VLAN `pn`/vlan0 up, DHCP 172.16.0.3; mini→node PN: 0.6 ms,
  **117 MB/s = M2 NIC line rate** (512MB HTTP pull).
- pf armed: pass `<vm_sources>` → 172.16.0.0/22:30000-32767 in
  /etc/pf.anchors/tuist.runners (persisted, before the 172.16/12
  block) + `nat on vlan0` in com.apple/tuist.vmnat (manually loaded —
  NOT reboot-durable; operator roll is the durable path). pf rule
  order gotcha: scrub MUST precede nat in the sub-anchor load.
- Staging deployed (helm rev 278/279/280) with images
  sha-8ec056e7c3dc (server + kura-controller), other pins unchanged.
- All 9 Paris KuraInstances Ready with exposeNodePort, clientCIDRs
  ipBlock in their NetworkPolicies, -external Services allocated.
- **kura_servers.url flipped to `http://172.16.0.2:<NodePort>` for all
  9 accounts** — the refresh loop works.
- Mini → `http://172.16.0.2:32675/up` (kura-tuist NodePort) = 200. ✓
- Smoke run 27416065883 SUCCESS, endpoint source dispatch,
  ROUTED_ENDPOINT http://172.16.0.2:32675 (the PN NodePort):
  - miss (cold): routed median 4.34s vs baseline 23.22s → **5.34×**
    (first iteration 46s = first-contact cache population outlier)
  - hit (warm): routed median 3.79s vs baseline 9.32s → **2.46×**
  - vs yesterday's WAN-tailnet numbers (4.4s/3.4s): equivalent at this
    small workload — latency-bound, not bandwidth-bound. The PN wins
    are structural: no WG crypto, no MSS clamp, separate bandwidth
    budget, 10 Gb/s ready for M4, tenant isolation.

## Bugs found & fixed during rollout (all committed)

- 34c5f3ccf7: manifest revision bump — instances created against an
  old CRD had exposeNodePort pruned and never re-applied (helm never
  upgrades crds/ on upgrade; staging healed by clearing the
  tuist.dev/kura-manifest-revision annotation on the scw instances).
- ea5e2a7788: nodes RBAC was in the controller's namespaced Role;
  Nodes are cluster-scoped → "nodes is forbidden" stalled every
  reconcile. Now a dedicated ClusterRole (`…-node-reads`).
- 10d07f737d: the server SA was a helm hook with before-hook-creation
  → deleted+recreated on EVERY deploy → all running pods' projected
  tokens 401 for up to ~45 min after each deploy (breaks runner
  dispatch TokenReview + kura reconciler). Migration Job now has its
  own hook SA; server SA is a regular resource. Staging SA was
  manually helm-adopted (meta.helm.sh annotations + managed-by label)
  — other envs (canary/prod) need the same adoption once before their
  first deploy of this branch, or the upgrade fails on ownership.

## Watch out

- Mini tailnet SSH (100.88.125.7) went DERP/unreachable mid-session;
  public IP 62.210.195.110 works with the fleet key. tailscaled on the
  mini worth a look.
- vmnat pf sub-anchor is hand-loaded (not reboot-durable) and there is
  no re-arm LaunchDaemon on this mini (handoff from 06-11 mentioned
  one; it does not exist). Durable config = macos-host-bootstrap
  operator roll (add VLAN + PN NAT support).

## Follow-ups / loose ends

- Durable mini config: extend macos-host-bootstrap for VLAN+PN NAT
  (replaces tailnet utun path for cache); operator drift only fires on
  binary SHA change (known limitation).
- apiserver kubelet-preferred-address-types += InternalIP (ClusterClass).
- scaleway-csi hostNetwork patch → upstream or wrapper.
- Node-join runbook/script for the pool (no CAPI provider for Scaleway
  instances — the operational gap vs the Hetzner kura pool).
- Drop (probably) the tailscale Connector proxyClass pin + macos
  accept-routes wiring from the branch at PR time — NodePort made the
  tailnet cache path obsolete. Keep tailnet for host mgmt only.
- Security hardening: node SG currently default-accept; tighten to
  cluster peers (vxlan 8472, kubelet 10250) + PN.
- Prod: region spec for prod project PN/CIDR, account count sizing,
  memory-limit knob, jumbo-MTU question to Scaleway support.
- Cut release tags after merge; drop staging pins.
- tuist-ops outage (Pomerium kubectl gateways) — separate task; use
  direct kubeconfigs ~/.kube/tuist-staging.yaml / tuist-mgmt.yaml.

## Mesh replication plan (2026-06-12, decided with Marek)

Goal: the per-account Scaleway runner-cache node must REPLICATE with the
rest of that account's Kura mesh (Hetzner runner nodes + the shared
public/regional pods), not run standalone.

Decisions locked:
- SINGLE cluster. All managed+private regions resolve
  `kubernetes_client_opts -> []` = in-cluster client; `cluster_id` is a
  logical label (instance name, public host, audit), NOT a physical
  cluster. So in-cluster `global_discovery_dns_name` peering works in
  staging AND prod (tuist-k8s-production). NO peer gateway needed; the
  #11173 KURA_PEER_GATEWAY_URL/KURA_PEERS path is for a future genuine
  multi-cluster only.
- PER-ACCOUNT CA (not shared). Required for both isolation AND function:
  today's controller auto-gens a PER-INSTANCE self-signed CA with SANs
  scoped to `<instance>-headless`, so two instances of the same account
  can't mutually authenticate. Per-account CA signs every instance leaf.
- Mesh-wide from the start (all accounts), not runners-gated.
- TLS facts (verified): client (reqwest) verifies server hostname
  against `resolved.host` = the account peer Service DNS
  (`kura-<account>-peers.<ns>.svc.cluster.local`); server
  (WebPkiClientVerifier) requires client cert chain to the trusted CA.
  => leaf SANs MUST include the account peer Service DNS; trusting only
  the account CA rejects cross-account peers at TLS.
- Replication model: eager push-on-write (outbox, bandwidth-limited,
  segment-level) + bootstrap catch-up (manifests/tombstones pages) on
  join. So cache CONTENT crosses the WAN on the background plane; the
  runner hot read/write path stays PN-local. PR narrative -> two-plane.

Implementation:
- kura-controller (Go): add `Mesh bool` spec field + CRD; flip
  `crossRegionRuntimeEnabled` to `Mesh || PeerTLSSecretName != ""`;
  controller-managed per-account CA secret `kura-<account>-peer-ca`
  (cert+key, account-scoped, no owner ref); per-instance leaf secret
  signed by the account CA with SANs covering the account peer Service;
  validate leaf chains to the live account CA.
- server (Elixir): set mesh: true on managed_region + private_region in
  regions.ex; emit "mesh" in the KuraInstance manifest.
- infra: open the peer port Scaleway<->Hetzner (node-SG hardening TODO).
- validate: bidirectional replication for one account, bootstrap on the
  scw node join, replication within bandwidth cap, runner read still
  PN-local, negative test (account B cannot peer with account A).
