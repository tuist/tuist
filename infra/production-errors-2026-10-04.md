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

The library is already preloaded, but bootstrap-only SQL never installed the
view on the existing cluster. Read-only database inspection found no
`pg_stat_statements` extension in the application database. The live Database
CRD supports extension reconciliation but rejects the reserved name `postgres`.

Adopt the configured application database through a CNPG Database resource,
using its existing owner, a `retain` reclaim policy, and only the requested
extension. Install the view in `public` and target that database from the
exporter. Fresh-cluster SQL and the manual recovery fallback use the same schema.
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

Four Helm regression tests cover extension/target alignment, custom names,
CNPG/query-stats gating, and cache deletion configuration. They failed before
the fixes and pass afterwards. Helm CI installs pinned PyYAML and runs them;
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

## Atlas issue-list caveat

Atlas's unresolved issue list identified muter submodule errors, Req HTTP/2
failures, manifest timeouts, and test-attachment expiry timeouts. Its list/get
responses expose issue metadata and lifetime counts, not a production-filtered
12-hour event history. The muter classifier already exists in deployed SHA
`929c11937db8`. Production registry logs do not reproduce those release errors
in this window, so no duplicate classifier or unproved expiry-worker fix was
introduced. The production ClaimSizingWorker checkout timeout is a separate
confirmed database event, not proof that test-attachment expiry timed out here.

## Validation and review

- Red then green: two dependency-free ExUnit production-config tests and four
  Helm/Python regressions.
- `python3 infra/helm/test-production-errors.py`: four passing tests.
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

Before promotion: deploy through the normal staging/canary/production sequence,
verify Database extension reconciliation and migration completion, confirm query
metrics appear and updater/scheduler errors stop, and monitor cache deletion and
upstream pull behavior. None of those deployment checks has been performed.
