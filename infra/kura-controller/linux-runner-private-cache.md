# Linux runner cache in OVH Gravelines

`ovh-gra-runners` is a private, Linux-only region on the
`kura-ovh-gra-runners` pool. Account caches use the managed two-replica lifecycle,
local XFS storage, and a 750 Mbps per-account ceiling. The replicas share the
staging cache host, so staging does not demonstrate host redundancy.

Runner dispatch prefers the active private instance's cluster Service and falls
back to the account's public-region Service while unavailable or disabled.
Availability is gated by `TUIST_KURA_AVAILABLE_REGIONS`. Enable it only after
both runner and cache hosts have converged and their physical path is verified.

OVH Kata hosts opt into the existing environment private-network reconciler
through `machine.vRackID`. This must match `capi.ovhPrivateNetwork.vrackID`.
The legacy RISE-S staging runner has no private NIC and must not be enrolled.
Address reservations, reciprocal routes, failure guards and membership
attestations use the existing managed private-network machinery.

## Staging rollout

1. Verify the prepared RISE-M runner and RISE-1 cache accept their fleet SSH
   keys and have healthy mirrored system and XFS data volumes.
2. Deploy the updated provider before enrolling the runner. Bring up the cache
   fleet and add the RISE-M runner alongside the legacy host. `OnDelete` keeps
   the old Machine until explicit retirement.
3. Wait for Ready, KataRuntimeReady and PrivateNetworkReady. Verify physical
   VXLAN traffic on both private NICs with no matching traffic on public NICs.
4. Move staging runner jobs to the new host before enabling `ovh-gra-runners`.
   Drain existing jobs normally. Verify account reconciliation and injected
   endpoint selection using a real GitHub Actions job.
5. Compare cold uploads and remote restores on the same runner against the
   colocated cache and the existing remote public-region cache. Disable local
   Gradle caching, prewarm dependency downloads and the daemon, alternate order,
   use fresh keys, verify every remote hit and restored payload checksum, and
   retain raw logs. Record the actual network path and endpoints; a cluster
   Service URL alone does not establish a physical private path.

Rollback removes `ovh-gra-runners` from available regions so new jobs use the
existing public-region fallback. Preserve in-flight jobs and their instances.
Do not clear the runner's vRack enrollment or recycle reservations while the
host still owns private routes. Production activation requires its own capacity
and path qualification; this change does not enable the region there.
