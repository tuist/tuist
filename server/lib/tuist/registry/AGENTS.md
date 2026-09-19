# Registry (Swift Package Registry writer)

The server-owned writer for the Swift Package Registry. Runs in the
`TUIST_MODE=swift_registry_sync` pod
(`infra/helm/tuist/templates/swift-registry-sync-deployment.yaml`) and is the
sole scheduled writer in managed environments. The read side is the standalone
pod in `registry/` — see `registry/AGENTS.md`. The two never talk; they share
one bucket and the key layout and metadata contract in
`tuist_common/lib/tuist_common/registry/swift/`.

## Responsibilities

- `SyncWorker` — cron-fired every 10 minutes on the `:web` leader, consumed
  here. Rotates through the SwiftPackageIndex catalog in batches via a cursor in
  object storage, and enqueues a `ReleaseWorker` per missing tag.
- `ReleaseWorker` — downloads one release from GitHub, builds the source
  archive, uploads it with its digest as object metadata, reads the object back
  to confirm the digest landed, then writes the catalog entry.
- `Metadata` / `S3` — the writer's object-storage surface.
- `Repair` — the gated entry point for bulk repairs that can replace published
  bytes.
- `Purge` — destructive removal. Not a repair; see below.

## The invariant this subsystem exists to protect

**A published version's bytes are immutable.** Swift Package Manager writes a
trust-on-first-use fingerprint under `~/.swiftpm/security/fingerprints/` the
first time it resolves a version. Republishing that version with different bytes
does not fail on our side at all: it fails on every developer machine that
already resolved it, with a checksum mismatch, and there is no way to enumerate
which machines those are.

The July and August 2026 incidents were a recovery that violated this. Restoring
availability by rebuilding versions changed 22,113 checksums across 1,643
packages, and the bucket had no object versioning, so the previously trusted
bytes were unrecoverable. Anything in this directory that can write over an
existing version has to be read with that in mind.

Three guards enforce it today, at different layers:

- `ReleaseWorker.ensure_checksum_change_allowed/5` refuses to republish a
  version whose rebuilt checksum differs from the published one, unless the job
  carries an explicit `allow_checksum_change`.
- `Repair` is the only supported way to set that override in bulk. It dry-runs,
  inventories the blast radius, bounds the batch, requires the operator to pass
  back the plan's approval digest, and backs up every archive it may replace.
- Object storage itself is still permissive: `S3.upload_file/3` is an
  unconditional write and the bucket has no versioning. Making a routine sync
  write physically unable to replace a published version is open work.

## Repairs

Never call `Registry.force_resync_swift_package_version/3` in a loop from a
console. That is the shape the 28 July recovery took, and it replaced 5,687
archives with nothing recording what changed and nothing to roll back to. Go
through `Repair`:

```elixir
{:ok, plan} = Repair.plan([{"auth0/Auth0.swift", "2.10.0"}])
plan.counts          #=> %{absent: 0, unresolvable: 1, published: 0, uninspectable: 0}
Repair.apply_plan(plan, approval: plan.approval)
```

`plan/2` writes nothing. `apply_plan/2` refuses without the plan's own approval
digest, refuses a batch over `Repair.max_batch/0`, refuses when more targets
than the threshold would be allowed to change a checksum, refuses if any
target's state could not be read, and stops any individual target whose
published checksum moved between the plan and the apply. The digest is
recomputed from the plan as handed in and covers the threshold as well as the
targets, so editing either invalidates the approval rather than travelling with
it.

Rollback is `Repair.restore/4`. It cancels outstanding repair jobs for the
version first: a job that snoozed on a rate limit still carries
`allow_checksum_change: true` and would otherwise republish the rebuilt bytes
over the restore once the quota resets. It then reads everything it needs before
replacing any byte, so a missing backup or an unreadable catalog fails cleanly.
The one unavoidable window is between the archive copy and the catalog write; if
that write fails the call returns `{:error, {:restore_incomplete, ...}}` naming
the state, and re-running finishes it.

`Purge` is a different thing and is not a repair. It deletes with no backup, and
every version it removes stops resolving until something republishes it.
`purge_package/3` requires a `confirm:` naming the package for that reason.

## Coverage is not availability

The sync pod can be `1/1 Running` with zero restarts and be mirroring nothing.
That is not hypothetical: during the incident it logged 2,566 GitHub rate-limit
failures and dropped nine consecutive scheduled passes in six hours while every
availability signal stayed green.

So throttling is deferred, never discarded. `SyncWorker` and `ReleaseWorker`
both return `{:snooze, seconds}` on a rate limit, sized to the reset GitHub
reports (`TuistCommon.GitHub.retry_after_seconds/1`), which keeps the job's
arguments. A pass that stops early advances the rotation cursor only over the
packages it actually visited, so the ones it never reached come up next time
rather than waiting a full rotation.

A 401 halts the pass the same way. The credential is not the repository, so
every remaining package would fail identically, and skipping them one at a time
would advance the cursor over the whole batch and report a clean run. A 403 is
deliberately not treated this way: GitHub uses it for repositories that are
individually unavailable, and halting on one would stall the rotation forever.

Not every miss halts. A package whose lock is held by a release worker is passed
over and the cursor moves with it, because contention there is ordinary and
sub-second. That miss is counted rather than silent
(`tuist_registry_swift_sync_package_skipped_total{reason="package_locked"}`).

A pass in which *every* package failed is read as one systemic failure rather
than as many independent ones: the cursor is held and the pass defers. Individual
per-package failures are survivable by design, which is exactly how they add up
to a clean-looking run that mirrors nothing, and a broken credential arrives in
that shape because GitHub answers an invisible repository with 404 rather than
401.

Lost coverage is a metric and a page, not a log line:
`Tuist.Registry.Swift.PromExPlugin` emits it and
`infra/helm/k8s-monitoring/alerts.md` carries the rules.

## GitHub credentials

`Registry.swift_registry_github_token/0` prefers a short-lived GitHub App
installation token and falls back to the personal access token
(`SWIFT_REGISTRY_GITHUB_TOKEN`). The personal access token spends one
user-scoped budget of 5,000 requests an hour across the whole catalog rotation
and every release job, and that is the budget the incident exhausted. The
production installation reports 12,500, the documented ceiling, and shares it
with nothing else.

`SWIFT_REGISTRY_GITHUB_APP_INSTALLATION` selects the installation, as the
organization the App is installed on (resolved and cached through
`Tuist.GitHub.App.get_installation_id_for_org/2`) or as a numeric installation
id.

The mirror reads repositories that are not part of the installation, which is
worth stating because the documentation does not: an installation token is
scoped to its installation's repositories for private data, but public data is
served to any valid credential regardless of scope. This was verified against
both the canary and production Apps before the cutover, across every endpoint
the mirror uses — tag listing, repository contents, single-file reads, zipball
download, and git clone credentials — against a public repository outside the
installation. It holds even though `contents` is not among the granted
permissions.

If that ever stops being true, the failure is loud rather than silent. GitHub
answers a repository a credential cannot see with 404 rather than 401, so it
would arrive as every package in a pass failing, which `SyncWorker` treats as
one systemic failure rather than as several hundred unrelated ones. A token
that cannot be minted at all logs and falls back to the personal access token.

`SWIFT_REGISTRY_SYNC_LIMIT` is the batch size and therefore what decides whether
one pass fits inside that budget: each package costs at least one tag-listing
request, plus one per extra page of tags.

## Related Context

- Read side: `registry/AGENTS.md`
- Shared key layout and metadata contract:
  `tuist_common/lib/tuist_common/registry/swift/`
- Deployment: `infra/helm/tuist/templates/swift-registry-sync-deployment.yaml`
- Alert rules: `infra/helm/k8s-monitoring/alerts.md`
