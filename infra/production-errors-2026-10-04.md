# Production error investigation, October 4, 2026

## Scope and evidence

Fixed window: **2026-10-03 20:28:35 UTC to 2026-10-04 08:28:35 UTC**.
Loki datasource: `grafanacloud-logs`, selector `cluster="tuist-production"`.
Cluster access used `kubectl --context tuist-k8s-production` for read-only logs,
Pods, deployments, events, CronJobs, backups, ConfigMaps, CRDs, and PVs.
Claude independently reviewed the diagnoses and the actual implementation.

No production resources, credentials, error-issue statuses, or S3 objects were
modified. No deployment was performed. Local validation included a disposable
PostgreSQL instance, removed after the check.

This is a grouped inventory with representative log inspection, not an export
of every event. The counts below are matching log **lines**, not incidents,
requests, or lifetime error-issue counts. The census matched `[error]`,
`level=error`, and JSON `"level":"error"`, case-insensitively. Unstructured
exceptions such as the backup failure were investigated separately. Kubernetes
events have shorter retention and are not a complete 12-hour history.

## Error-line inventory

| Namespace / container | Lines | Investigation / disposition |
| --- | ---: | --- |
| tuist-runners / dind | 65,879 | Samples include exec-attach broken pipes, missing buildx cgroups, unsupported GPU requests, and containerd EOFs. Only 256 match `Failed to get event`; do not dismiss the entire count as shutdown noise. Job-level failure correlation remains open. |
| slack / slack | 14,387 | Repeated tzdata updater crashes on a read-only release. Local fix below. |
| noora / storybook | 14,386 | Same tzdata failure. Local fix below. |
| tuist / postgres | 4,320 | Missing `pg_stat_statements` view in the exporter's database and resulting transaction rollbacks. Local fix below. |
| Host / unlabeled container streams | 2,437 | Not attributed to a Kubernetes container by the census; needs separate host-stream classification. |
| tuist / server | 1,337 | Predominantly ClickHouse connection disconnects. The non-ClickHouse query returned 20 lines: Bandit read timeouts, GitHub release-fetch timeouts, and a ClaimSizingWorker PostgreSQL checkout timeout. No speculative timeout increase or logging suppression. |
| local-path-storage / local-path-provisioner | 1,152 | Repeated missing helper-Pod errors for 12 Released local PVs pinned to an absent retired Dedibox node. Operational cleanup requires scoped human authorization. |
| tuist / processor | 445 | All matched errors disappear when excluding `Ch.Connection`. Connection recycling must be distinguished from failed queries before changing pooling. |
| kura / demux | 348 | Requires separate attribution of peer-demultiplexer errors; one inspected sample was an empty upstream for a client connection. |
| observability / node-exporter | 170 | Inspected samples: mdadm collector cannot parse RAID status. Host collector diagnosis remains open. |
| tuist / swift-registry-sync | 90 | ClickHouse disconnect bursts. Also 23 HTTP/2 `closed_for_writing` warnings in the pod log. No `Failed to sync release`, muter, or manifest-fetch exception matched production in this window. |
| observability / alloy | 65 | Samples include memberlist timeouts, Faro source-map 404s, and permanent Tempo `TRACE_TOO_LARGE` rejection at 150 MB. Do not silence these or conflate them with Kura exporter errors. |
| kura / manager | 62 | Controller error category inventoried; not fully diagnosed in this pass. |
| kube-system / coredns | 38 | Inspected samples: upstream DNS UDP timeouts. Network diagnosis remains open. |
| tuist / registry-cache | 8 | TTL scheduler's manifest deletion is unsupported without storage deletion enabled. Local fix below. |
| kura / kura | 7 | All seven inspected JSON ERROR lines were OTLP network export failures on `sa-west-1` pods. Export target is in-cluster Alloy port 4318. Cause is not proved; no exporter disabling or speculative network-policy change. |
| platform / controller | 3 | Inventoried; not fully diagnosed. |
| platform / manager | 3 | Inventoried; not fully diagnosed. |
| tuist / plugin-barman-cloud | 1 | ObjectStore status-update conflict, not proof of backup failure. PostgreSQL's October 4 daily backup reports `completed`. |
| tuist-ops / tuist-ops | 1 | Inventoried; not fully diagnosed. |

## Regression-backed local fixes

### Slack and Storybook: immutable timezone data

Both updater processes restart about every three seconds after `File.write!`
tries to update `/app/lib/tzdata-*/priv/latest_remote_poll.txt` on a read-only
filesystem. Disable tzdata autoupdate in production, preserving the bundled
rules and filesystem hardening. Rules must be refreshed through dependency
updates and redeploys. This also follows Atlas's existing immutable-data policy.

Two ExUnit regressions read each application's merged production configuration.
They failed before the fix and pass afterwards. Storybook's check is explicitly
wired into Noora CI; the root Noora test suite does not run Storybook tests.

### CNPG: reconcile the extension on existing databases

The library is already preloaded, but no `pg_stat_statements.*` parameter
enables CNPG's built-in extension manager. That manager removes the extension
when enabling parameters are absent, even if bootstrap SQL or a Database CR
creates it. Staging exposed this conflict: the Database reported the extension
applied while live SQL found the view missing. CNPG 1.29.1's instance-controller
source confirms the removal behavior. The live Database CRD supports extension
reconciliation but rejects the reserved name `postgres`.

Adopt the configured application database through a CNPG Database resource,
using its existing owner, a `retain` reclaim policy, and only the requested
extension. Install the view in `public` and target that database from the
exporter. Default `pg_stat_statements.track` to `top` when query statistics are
enabled, preserving explicitly configured tracking values, so CNPG retains the
extension. Fresh-cluster SQL and the manual recovery fallback use the same schema.
CNPG >= 1.26 is required only when the opt-in query-stats feature is enabled.
The managed operator supports this API. Existing `citext` and `uuid-ossp`
extensions are not removed or upgraded.

The template explicitly warns against `spec.ensure: absent`: that would drop
the application database regardless of the retain reclaim policy. The retain
policy protects deletion of the resource, not an explicit database-drop request.

### Docker Hub pull-through cache: enable its expiry operation

Enable `REGISTRY_STORAGE_DELETE_ENABLED=true` only on the cache Deployment.
The cache's intended TTL scheduler can then delete expired entries. This is an
S3-backed persistent cache under `docker-mirror/`, not ephemeral Pod storage.
Do not claim that restarting it clears old objects or that this fix reclaims
previously orphaned entries. Client deletion remains unsupported in proxy mode.
Watch S3 deletes and upstream re-fetches after rollout; retain the single replica.

Eight Helm regression tests cover extension/target alignment, custom names,
CNPG/query-stats gating, tracking parameters, cache deletion configuration,
and staging rack-agent scheduling without changing other environments' defaults.
The original regressions and staging-discovered cases failed before their
respective fixes and pass afterwards. Helm CI installs pinned PyYAML and runs them;
the script lives outside the packaged chart.

## Critical unresolved issue: ClickHouse backup recovery

October 4's incremental cannot find `full/2026-W40`. Its fallback full fails with
`BACKUP_ALREADY_EXISTS`, saying the path "is being written already". Retained
October 2 and October 3 logs show the same two-step failure.

The September 28 full failed after roughly 2h17m with an **8 GiB user memory
limit**. That memory configuration was already corrected in main to a 24 GiB
backup budget by #13661. Reintroducing that fix would be redundant. A leftover
write marker or incomplete prefix is a plausible explanation of the current
failure, but it was not verified by listing S3 objects or querying live backup
state.

The incremental CronJob's **last recorded successful run is September 25,
2026 at 01:02:18 UTC**, more than nine days before this investigation. The full
CronJob has no recorded `lastSuccessfulTime`. This is an urgent scheduled-backup
coverage gap, not evidence that no other backup exists: actual stored backups
and their restorability still need verification.

Recovery actions:

1. Read the live backup status and inventory the W39/W40 backup objects through
   the authorized database/storage path; identify and verify a restorable point.
2. Before any W40 cleanup, prove there is no active writer and identify precisely
   which incomplete objects are safe to retire. Obtain human-approved elevation
   whose intent covers that recovery. Do not automatically delete a backup prefix.
3. A newly named full backup or the scheduled **October 5 01:00 UTC W41 full**
   may avoid the blocked W40 path. Neither has been validated as successful.
   Treat waiting for Monday as a risk decision, not a guaranteed recovery.
4. Verify completion and perform a bounded restore check; Pod readiness or a
   larger memory budget is not proof that the backups are usable.

## Atlas follow-up and environment attribution

Atlas's list/get responses expose last-seen timestamps and lifetime counts,
not a production-filtered 12-hour event history. A subsequent review of the
100 most recently seen unresolved issues used their timestamps to find matching
Loki events across production, canary, and staging. This is not an exhaustive
review of the historical backlog, and issue statuses were left unchanged.

- **Muter submodule failures:** the October 4 08:53:54 event is from staging's
  `swift-registry-sync`, running `sha-0b93604a05fb`, which predates the classifier
  fix in #13770. The classifier already exists in production's inspected SHA
  `929c11937db8` and this branch. Update staging rather than introduce a duplicate
  code fix. Atlas's 2,887 events are a lifetime total, not this window's count.
- **Req HTTP/2 `closed_for_writing`:** the October 4 08:33:50 release exception
  also comes from staging. It is a separate transport failure, not the permanent
  submodule classification problem. No transport fix is claimed by this PR.
- **Test-attachment cleanup timeouts:** production has three matching Oban
  exception events at 02:30:22, 02:30:52, and 02:32:27 on October 4. They are
  logged at info level and were missed by the original error-level census.
  This corrects the initial conclusion that production occurrence was unproved.
  Each first-attempt job ran for about 11 seconds and returned `{:error, :timeout}`.
  These events do not establish whether storage deletion or another operation
  timed out; inspect retries and dependencies before changing timeouts or pooling.
  The ClaimSizingWorker checkout timeout is a separate event.
- **Kura telemetry export:** the 08:30:20 Atlas occurrence matches production's
  `kura-pinterest-sa-west-1-0` BatchSpanProcessor HTTP export failure. This is the
  same unresolved exporter/network category already inventoried above. The
  lifetime total of 22,144 does not imply that many recent cache-request failures.
- **Cache globe DateTime query parameters:** the 728-event issue was last seen
  October 2 at 11:47:15. The whole-second truncation fix already exists in #13788
  and this branch. Its unresolved status alone does not prove a current failure.

Manifest-fetch timeouts, build and xcresult processing failures, retention,
pooling, and other older issue groups still need targeted follow-up. The local
configuration fixes in this PR do not claim to resolve that backlog.

## Validation and review

- Red then green: two dependency-free ExUnit production-config tests and four
  Helm/Python regressions.
- `python3 infra/helm/test-production-errors.py`: eight passing tests.
- `python3 infra/helm/test-staging-monitoring.py`: two passing tests, including
  a clean Helm repository configuration after adding the locked dependency's
  Grafana repository explicitly.
- `elixir -e 'ExUnit.start(); Code.require_file("slack/test/slack/production_config_test.exs"); Code.require_file("noora/storybook/test/production_config_test.exs")'`: two passing tests.
- Storybook's exact standalone CI command passes from `noora/`.
- Full production `helm template` with common, production, and CI values passes.
- `kubeconform -strict -ignore-missing-schemas`: 193 valid resources, zero
  invalid/errors, 41 skipped resources whose schemas were unavailable. This is
  not validation of every custom resource.
- `actionlint` 1.7.12 with shellcheck 0.11.0 passes after ignoring the pre-existing
  unknown `tuist-linux` custom-runner-label warning.
- Disposable local **PostgreSQL 18.3**: app-owner `GRANT` and `REVOKE ... ON ALL
  TABLES IN SCHEMA public` succeed with the superuser-owned extension views.
  They emit expected warnings; existing extensions remain present. This is not
  a staging migration or operator-reconciliation test.
- Elixir source formatting and `git diff --check` pass.
- Claude challenged both the diagnoses and implementation, catching redundant
  backup-memory work, unsafe reserved-database adoption, stale documentation,
  CI/packaging gaps, and the persistent S3-cache tradeoff. Those implementation
  findings were addressed; the final solution review reported no blockers.

## Staging rollout and live validation

Staging deployment [37199348746](https://github.com/tuist/tuist/actions/runs/37199348746)
completed after narrowly scoped live repairs. A second deployment,
[37203051378](https://github.com/tuist/tuist/actions/runs/37203051378), successfully
replayed the committed chart fixes from `3a44cee6891c` without further manual
patches. Application, registry, and codebase-search images reuse
`sha-907b3c0d66c5`; platform configuration revision 498 and unrelated fleet/runtime
pins were preserved. No canary or production deployment was dispatched.

Deployment blockers and recovery:

- The two BER1 edges have had disconnected kubelets and tailnet peers since
  September 28 around 19:27 UTC. Their owned Nodes, Machines, and hosts were
  not deleted. The underlying physical power/network failure is not diagnosed;
  both-offline AMT relay dependence still prevents remote recovery.
- Staging node-exporter now tolerates explicit infrastructure roles rather than
  every `NoSchedule` taint. Two already-terminating, read-only exporter Pod
  records on disconnected hosts were removed with UID preconditions to unblock
  the rolling update. All eligible exporters were updated and Ready: **11/11**
  in the final snapshot. This count follows the current live node inventory.
- The staging rack-node-agent also excluded unreachable scheduling targets.
  Unlike the exporter, it retains NotReady toleration so it can repair local
  CNI. The disconnected hosts are not readiness targets while offline; their
  privileged agent Pod records were not force-deleted. Other environments keep
  their original agent tolerations, and Helm readiness waits remain enabled.
- During the first application rollout, both general-purpose cloud workers
  became unavailable and CAPI began replacement. The staging API temporarily
  timed out and the public endpoint returned HTTP 525. Existing management
  access was used only for read-only diagnosis; no administrative credential
  was fetched or permission expanded. Replacement proceeded through the owning
  controllers. The underlying worker failure is still unproved.
- One terminating PostgreSQL Pod record stalled the drain. Its logs confirmed
  PostgreSQL and its manager had completed shutdown, and `pg_controldata` showed
  a clean shutdown. Only that record was removed with UID/resource-version
  preconditions; its PVC was retained. The controller subsequently completed
  volume detachment and worker replacement. No volume or backup was deleted.
- Recovery left most stateless workloads on one replacement worker, preventing
  a 1 GiB PostgreSQL replica from fitting there despite free capacity elsewhere.
  One stateless processor Pod was restarted with its normal termination grace.
  It moved to the less-loaded worker, allowing the replica to schedule. Both
  workers and PostgreSQL instances recovered.
- Live SQL then caught the CNPG extension-manager conflict described above.
  A dry-run-validated staging parameter patch enabled tracking. The committed
  chart now supplies the same parameter; declarative status alone was not
  treated as sufficient evidence.

Live results on October 4, approximately 12:39–12:51 UTC:

- Both deployment runs succeeded, including the application migration Job.
- CNPG reports **2/2 Ready**, `Cluster in healthy state`, with primary
  `tuist-tuist-pg-2`. The committed `pg_stat_statements.track: top` setting is
  present after the replay.
- Read-only SQL confirms database `tuist`, owner `tuist_app`, and
  `public.pg_stat_statements`. Existing `citext`, `uuid-ossp`, and `plpgsql`
  remain present. Exporter schema/table privileges are valid.
- Both instance exporters expose `cnpg_tuist_query_stats_*` samples and
  `cnpg_last_error 0`, with no missing-view error sample in those scrapes.
- Application `/ready`, Swift registry `/up`, registry protocol availability,
  and `swiftlang/swift-syntax` release metadata return HTTP 200.
- The Docker mirror serves an Alpine 3.22 OCI index with HTTP 200 when the
  request includes the appropriate OCI Accept header. Two exploratory requests
  without that header returned expected `MANIFEST_UNKNOWN` errors; they are
  not expiry failures.
- The cache's TTL scheduler started and deletion is enabled. Logs from
  **12:02–12:51 UTC** contain no error-level expiry/deletion failures. The
  existing repository/tag-remover warning remains. No controlled expiry cycle,
  S3-delete verification, or historical orphan cleanup was performed, so this
  observation is not proof of a complete cache TTL cycle.

Slack and Storybook's immutable-timezone configuration is covered locally and
in CI, but their production-only deployment workflows were not run for staging.
Before promotion, verify their deployed behavior, continue cache-expiry
observation, and resolve the ClickHouse backup/restore risk. Staging success
neither repairs the rack nor resolves the separate Atlas backlog.
