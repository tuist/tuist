# Linux runners: direct regional caches on one pool

Every Linux job shares the existing `runners-linux` host pool and receives its
account's existing regional Kura Service URL. There is no cache-path account
flag, alternate runner cohort or WAN relay. Eligible OVH hosts use vRack for
all accounts after network enrollment. No new cache hosts or cache instances
are required. macOS private-cache behavior is unchanged.

Linux prefers the existing EU-West instance, falling back to another active
managed region when EU-West is absent. The selected primary, authorization,
contents, storage accounting and move identity remain unchanged. Host routes
also match cache nodes' public IPs, so using a public hostname would not provide
an account-specific WAN treatment. This rollout intentionally applies to all
jobs on an enrolled host; account opt-out is no longer part of the design.

## Rollout

Canary's Gravelines RISE-M is `ns3127017.ip-51-68-34.eu`, Machine/Node
`tuist-tuist-ovh-fleet-runners-linux-gnbmk-jgl25`. It uses the existing Canadian
`kura-tuist-ca-east-1` cache. Production has ten RISE-L runners and six existing
EU-West cache hosts. Refresh inventory and load before changing either fleet.
Canary validates transport and correctness, not Gravelines-local latency.

1. Verify no queued, claimed or running jobs reference retired `-vrack-` pools.
   Deploy the shared-pool server/chart changes through the reviewed pipeline.
   Preserve existing pool sizing, cache-agent coverage and Machine identities.
2. The canary and production runner templates declare `vRackID` values
   `pn-2024092` and `pn-2024093`. Existing OnDelete hosts require a drained
   backfill of the same field. Drain one runner at a time, without deleting or
   reinstalling its Machine or changing its pool. Ensure the cache peers are
   enrolled in the environment's existing private network as well.
3. Require private-network readiness, reciprocal-route attestations, full-MTU
   connectivity and Kata readiness before returning the host to service. Verify
   the actual route and interface traffic; a direct Service URL alone does not
   prove PN transport. Retain the existing unreachable guards.
4. Run the canary Gradle smoke on the enrolled host. Require a fresh upload and
   remote `FROM-CACHE` restore with matching output and local caching disabled.
   Check ordinary public-client access and cache health. Then enroll production
   hosts one at a time and repeat the path/restore validation against the existing
   Gravelines instances. No account enrollment step is involved.

Human canary/production elevation is required for live mutations; see
[cluster access](../AGENTS.md#cluster-access-for-agents). Host network rollback
is a drained maintenance operation; clearing `vRackID` alone does not safely
remove installed routes. Repeating the live rollback drill is excluded at the
user's request. Removing the obsolete flag from code does not require deleting
its historical database records during the rolling upgrade.

## Validation

Use `linux-runners-staging-smoke.yml` with `gradle_cache=true`,
`runner_label=tuist-canary-linux`, `server_url=https://canary.tuist.dev` and
`project=tuist/tuist` for the canary Gradle upload/restore check. Despite its
historical name these inputs select canary. Leave other options off: the real
Kotlin compilation, request latency and regional benchmark helpers still enforce
staging/EU-West, and the hold/restart drill is staging-only.

The [ordinary canary baseline](https://github.com/tuist/tuist/actions/runs/40473996831)
passed before enrollment: a fresh Gradle key was uploaded and restored with
matching output through the existing Canadian instance. It did not prove private
transport. Measure metadata/HEAD and object reads on the same instance before
and after enrollment, including concurrent builds, errors, p95, CPU, memory,
disk and link pressure. Keep logs and captures in workflow artifacts rather
than dated repository validation directories.

Historical measurements in [#14766](https://github.com/tuist/tuist/pull/14766)
used a dedicated Gravelines instance versus Canada with different egress limits.
They do not establish the final same-instance production performance.

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
   existing regional cache before qualifying its already
   enrolled RISE-M. Remove the obsolete stored flag only once no old server
   depends on it. The old RISE-S OVH contract was cancelled by the user.

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
