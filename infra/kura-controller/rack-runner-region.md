# One runner-cache region across the rack sites

`ber1-runners` spans both Berlin rack sites: one replica per account on each
site's storage node (ber1-store-a at alder, larch-store-a at larch), so a Kura
rollout replaces one replica while the other serves. It ships before the
private inter-site link; the sites' pods already reach each other over the
Cilium overlay between the storage nodes' WAN addresses
(infra/rack-nodes/AGENTS.md, "A storage node on the cluster network").

## Shape

- **Region.** `ber1-runners` keeps its id, cluster id `ber1` and private host,
  so instances (`kura-<handle>-ber1`), their claims and the URLs running jobs
  hold do not change. It sets `replicas: 2`, the node selector
  `tuist.dev/kura-runner-region: ber1-runners` (on both storage nodes) and
  `replica_spread_topology_key: tuist.dev/rack-storage`.
- **Placement.** The controller renders `spec.replicaSpreadTopologyKey` as a
  required pod anti-affinity on that label, so the two replicas never share a
  site. Capacity counts at most one replica per label value
  (`Capacity.placements/2`), so larch's spare disk cannot stand in for ber1's.
- **Serving.** Only the controller's selected primary serves. ber1's Macs reach
  it through the private host on ber1's gateway (`gateway_node_selector`, pool
  `rack-storage-ber1`). larch's Macs reach it through the
  `<handle>-ber1-runners-via-larch` entrance on larch's gateway
  (`entrance_sites`, class `kura-larch-runners`, CIDR `10.20.0.0/24`). The
  gateways proxy to the primary wherever it runs, so the rack whose Macs cross
  the internet is the one without the primary; a rollout or failover can swap
  it.
- **Limits.** The entrance is larch's front door rather than a fallback, so it
  has no rate or connection limit.
- **Accounting.** `RunnerCache` counts traffic, job runs and drain waits at
  every site the region serves (`Regions.sites/1`).
- **larch-runners.** Marked `draining`: it stays in the catalog but admits no
  account, so `RunnerCache` drains any node in it.

## Migration (2026-11-25)

1. **Drain `larch-runners`.** Its five nodes drained without restarting and
   were destroyed 15 minutes later, freeing larch-store-a's memory (12.21 GiB
   allocatable, 1.64 GiB of other pods: room for five 2 GiB replicas). Larch
   jobs fell back to their ber1 node through the rate-limited entrance.
2. **CRD and controller** with `replicaSpreadTopologyKey`. An instance without
   the field renders as before.
3. **Node labels.** kubelet applies `--node-labels` only at registration, so
   the running nodes were labelled by hand:
   `kubectl label node ber1-store-a larch-store-a tuist.dev/kura-runner-region=ber1-runners`.
   The fleet values carry the label for future registrations.
4. **Merged region (server).** Every `ber1-runners` instance re-applies with a
   new revision. The StatefulSet (Parallel, RollingUpdate) creates ordinal 1 on
   larch-store-a and restarts ordinal 0 only once ordinal 1 is Ready, so
   ordinal 0 keeps its ber1 volume and the account always has a replica.
   Ordinal 1 starts empty and fills from ordinal 0 over the overlay; while
   ordinal 0 restarts, ordinal 1 serves and may miss. Check with
   `kubectl -n kura get pods -l app.kubernetes.io/name=kura -o wide`: every
   account should have `-0` on ber1-store-a and `-1` on larch-store-a.
5. **Follow-ups.** Delete the `larch-runners` region spec once nothing refers
   to it. Ship the plan-sized memory floors (`memory_governed`), which roll
   one replica at a time now, to make room at larch for more accounts.

## Known gaps

- **tuist is off the rack cache.** The claims on ber1-store-a total 626 GiB of
  about 777 GiB allocatable, so `Capacity.room_for?` refuses tuist's 256 GiB
  claim; its jobs use the public cache until ber1 has room or the claim
  shrinks.
- **No memory headroom at larch.** About 0.57 GiB stays free, so no new rack
  account is admitted until the memory floors shrink.
- **Overlay encryption.** No WireGuard or IPsec setting was found for Cilium,
  so replication and the gateways' proxying between sites likely cross the
  internet unencrypted. Kura authenticates every request, but cache contents
  cross in the clear.
- **WAN bandwidth.** Ordinal 1's initial fill copies every account's cache
  (up to 626 GiB of claims) across both sites' billed internet ports, and one rack's Mac
  traffic crosses them afterwards. Neither site's bandwidth has been measured.
