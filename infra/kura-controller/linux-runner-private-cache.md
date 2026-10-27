# Linux runners: account-selected cache paths on one pool

Linux jobs share the existing `runners-linux` host pool. The default-off
`runner_linux_vrack` account flag selects the cache path at job claim, not a
runner fleet, machine or cache instance. Initial enrollment is Tuist only.
macOS private-cache selection is unchanged. No new cache hosts are required.

## Paths and isolation

Both paths select the account's existing managed EU-West Kura instance, or
another active managed region when EU-West is absent. They retain the same
primary Service, authorization, contents, storage accounting and move identity.

- Flag on: dispatch injects the instance's direct internal Service URL. On a
  qualified, enrolled OVH runner, the host's reciprocal routes carry this
  connection over vRack.
- Flag off: dispatch injects an owner-bound `wan-<digest>.kura.svc.cluster.local`
  Service. Its backend is a shared WAN relay on the existing Hetzner Cloud
  general-purpose nodes. The relay opens a new connection to the same Kura
  primary Service. Neither connection terminates on two vRack participants,
  so the runner's host-wide peer routes cannot silently turn it into PN traffic.

A public hostname alone cannot separate these paths: the existing private
routes also match cache nodes' public IPs. The relay avoids changing that
proven routing and its unreachable guards. It costs an extra hop on the ordinary
path; include that hop when reporting performance. This is rollout selection
for the managed cache client, not a new artifact authorization boundary: Kura
still verifies each request, and untrusted workflow code must never be given
operator credentials.

The Kura controller creates one alias Service per public instance. Alias names
are `wan-` plus the first 32 lowercase hexadecimal characters of SHA-256 of the
exact internal Service name, including the `-m` move suffix. The alias has the
instance's owner reference and routes only to the relay pods; deletion follows
the existing instance lifecycle. The relay uses a watched Service catalog and
accepts only aliases whose owner, label and backend annotation agree. It does
not accept arbitrary upstream URLs. HTTP and h2c gRPC bodies stream through;
authorization/status/trailers are preserved. Endpoint redirects are suppressed
and unexpected redirects fail closed rather than escape to a direct path.

The relay has two replicas on separate `general` nodes, a disruption budget,
no private-network scheduling label, no cloud credentials and read-only API
access to Services plus its startup Node check. It refuses to start unless its
Node's provider ID is Hetzner Cloud and the Node is not private-network enrolled.
No direct fallback occurs when the relay is unavailable. Authenticated cache
failure then follows each client's existing error behavior.

`kuraController.runnerCacheRelay.enabled` prepares the relay, controller aliases
and server endpoint selection together. Initial rollout enables it on canary
only. Staging, production and self-hosted installs keep their existing endpoint
behavior until explicitly prepared; the same capability is available in each
environment.
This infrastructure setting does not enable any account flag. Do not enroll
hosts before relay readiness and ordinary-path verification.

## Deployment and canary qualification

Canary can qualify this before staging's old experiment is migrated. Its
Gravelines RISE-M is `ns3127017.ip-51-68-34.eu`, represented by Machine/Node
`tuist-tuist-ovh-fleet-runners-linux-gnbmk-jgl25`. Its current cache is the
existing `kura-tuist-ca-east-1` in Canada. That qualifies routing and restores,
not Gravelines-local latency. Both flagged and excluded jobs can use this one
host concurrently; no cohort switch or extra runner is needed.

1. Before removing the old isolated RunnerPool resources, verify that no
   queued, claimed or running job retains an old `-vrack-` pool. Finish such
   jobs before deployment; do not delete a live runner to force migration.
2. Deploy the refactor through the reviewed chart/runtime pipeline. Verify
   relay replicas Ready on separate Hetzner general nodes and the account's
   alias Service selects them. With the account flag off, run the ordinary
   smoke, verify its injected alias and existing backend identity, and capture
   the public/private interfaces to establish the WAN path.
3. Drain the existing runner for its initial network enrollment. Keep its
   Machine identity and `runners-linux` membership. After the reviewed template
   declares `vRackID: pn-2024092`, backfill that field on the existing OnDelete
   OVHDedicatedMachine. Wait for private-network readiness, reciprocal-route
   attestations, full-MTU reachability and Kata readiness before uncordoning.
   No Machine deletion, reinstall, pool relabel or additional host is involved.
4. Enable `runner_linux_vrack` only for Tuist through audited flag control.
   Run positive and excluded-account jobs on the same host; record the actual
   injected endpoints and cache instance. Verify PN traffic for Tuist, WAN
   traffic for the excluded account, matching Gradle remote restores, normal
   public-client access and relay/cache resource headroom. Do not claim a
   private-path result from a Service name alone.

Human canary/production elevation is required for live mutations; see
[cluster access](../AGENTS.md#cluster-access-for-agents). Flag disablement changes
new claims to the relay after the existing bounded flag-cache propagation. It
neither migrates running jobs nor removes host routes. A repeated live rollback
drill is excluded from the current canary qualification at the user's request.
Host network rollback remains a separate drained maintenance operation; clearing
`vRackID` alone does not safely remove installed routes.

The [ordinary canary baseline](https://github.com/tuist/tuist/actions/runs/40473996831)
passed before this refactor on the unenrolled RISE-M: a fresh Gradle key was
uploaded then restored with local caching disabled and matching output through
`kura-tuist-ca-east-1`. It did not test the relay or private path.

## Reusable probes

Use `linux-runners-staging-smoke.yml` with `gradle_cache=true`,
`runner_label=tuist-canary-linux`, `server_url=https://canary.tuist.dev` and
`project=tuist/tuist` for the simple canary Gradle upload/restore check. Despite
the workflow's historical name, these inputs select canary. Leave the other
options off: the real Kotlin compilation, request latency and regional benchmark
helpers still enforce staging/EU-West, and the hold/restart drill is staging-only.

Record the same account and existing instance before/after enrollment. Measure
metadata/HEAD and object reads, include concurrent builds, and monitor errors,
p95, queueing, CPU, memory, disk and link pressure. Keep logs and captures in
workflow artifacts, not dated repository validation directories. Public clients
share the same instance, so their health is part of qualification.

## Staging migration remains separate

Staging still needs the old `ovh-gra-runners` experiment retired before this
release is deployed there. The current request leaves staging alone.

1. On the old server release, inventory old-region rows, KuraInstances,
   Services, pods and jobs retaining their URLs. Remove every enrollment of
   `kura_linux_runner_cache`; a global false alone does not override actor or
   percentage gates. Verify ordinary regional selection for new jobs.
2. Preserve old-region reconciliation while normal lifecycle drains it. The
   minimum drain is 15 minutes with job protection up to six hours. Require no
   non-destroyed old-region rows or serving CRs/pods/Services; a timer alone is
   not proof. Do not rewrite a live instance's region in SQL.
3. Reuse `ns3220989.ip-162-19-86.eu` as ordinary EU-West capacity. Preserve the
   `gra-runners-cache` fleet identity/adoption prefix and update its persistent
   cache pool to `kura-dedibox` without Machine replacement. This host also holds
   the migrated RISE-S fixtures and retained recovery archives: do not reinstall
   it or delete those backups. Verify fixture scheduling, storage, public
   DNS/TLS, ingress and capacity before deploying the new region catalog.
4. Staging then advertises `scw-fr-par-runners,eu-west,ca-east`. Verify its
   existing regional cache and relay aliases before qualifying its already
   enrolled RISE-M. Remove the obsolete stored flag only once no old server
   depends on it. The old RISE-S OVH contract was cancelled by the user.

## Production

Refresh live inventory and load before enrollment. Existing production caches
in Gravelines are reused; no dedicated runner caches or extra logical regions
are introduced. Deploy and qualify the ordinary relay first. Drain and enroll
compatible existing runner hosts into `pn-2024093` without changing their pool,
then enable only Tuist after private transport qualification. Hosts still lacking
private connectivity retain a WAN path; do not interpret a direct endpoint alone
as proof that a job used PN. Qualify every host eligible for the shared pool
before relying on the flag as a consistent performance treatment.

Historical measurements in [#14766](https://github.com/tuist/tuist/pull/14766)
compare an earlier dedicated Gravelines instance with Canada, with different
egress ceilings. They establish neither this relay's overhead nor the final
regional-instance reuse performance. Production activation remains pending fresh
canary path/isolation validation and same-instance production measurements.

## Staging fixture preservation, 2026-10-26

Before retiring `ns340020.ip-37-187-143.eu`, both remaining fixture replicas
were moved from the RISE-S to the existing Gravelines cache host:

- `kura-spec98/kura-matrix-oct22d`: planned handover verified 316,078 retained
  records, revoked the old writer, and moved serving authority to ordinal 0.
  Supported replica recovery rebuilt ordinal 1 on Gravelines and reached
  `Verified`; both replicas are Ready with initial backfill complete. A fresh
  synthetic PUT returned 204 and GET returned 200 with the expected value.
- `kura-spec98/kura-handover-oct9`: its standby exited cleanly, then its 32 MB
  volume was copied cold within staging. All 22 file checksums matched before
  restarting ordinal 1 on Gravelines with its existing `0.58.0-canary.13`
  runtime. Both replicas are Ready. The pre-existing expired epoch-3 `Fencing`
  grant remains unchanged; this migration does not repair that fixture's
  unavailable serving authority or reset its durable floor. The instance's
  template and fenced image pin now match that standby runtime; OnDelete
  preserves ordinal 0's existing runtime.

The original matrix and handover volumes, plus an older released quarantine
from `kura-spec98-final-1`, have checksum-verified archives on the Gravelines
cache host in PVC `kura-spec98/rise-s-migrate-matrix-oct22d` (PV reclaim policy
`Retain`). `rise-s-retirement-backups` in that namespace records the archive
names and SHA-256 hashes. Preserve these archives until explicitly cleaned up;
the quarantined archive retains its unclean-primary marker and is not a volume
to start as a writer. Temporary copy pods, their NetworkPolicy and the pod
finalizer used during the cold move were removed. Host release wipes local
disks, so the retained archives are the preservation copies after retirement.
Removing the Machine does not cancel the OVH monthly contract.
