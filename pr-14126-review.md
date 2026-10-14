# Review: tuist/tuist#14126 (cache volume commit controls)

The core design holds up. Write permission comes only from the job data GitHub returns, never from workflow input. Allocation, publication and policy edits all run under the same volume row lock. Explicit `true`/`false` modes fail rather than being silently ignored when part of the fleet runs older versions.

## Worth fixing before merge

### 1. Tag runs can match writer branches

`server/lib/tuist/runners/cache_volumes/identity.ex:100`

For `push` and `workflow_dispatch` events, `github_writer_branch` returns `run["head_branch"]`. GitHub sets that field to the tag name when the run comes from a tag. A tag named like a granted branch therefore gets that branch's publish rights.

Scenario: an admin grants `release/1.0`. A contributor with write access who can't push to the protected `release/1.0` branch pushes a tag named `release/1.0` (tag protection rules are separate from branch rules). The tag run publishes over the shared snapshot. No test covers a tag run.

Suggestion: only grant when the run's ref is a branch, not a tag.

### 2. Any policy edit revokes in-flight default-branch saves

`server/lib/tuist/runners/cache_volumes.ex:226`

Every changed policy sets `can_publish = false` on all pending uses, including trusted default-branch jobs whose permission doesn't depend on `writer_branches`. Usage rows don't record why permission was granted, so the code can't revoke only the grants a removed branch gave.

Scenario: an admin adds an experiment branch while a 40-minute `main` job is running. That job's snapshot is discarded and main's cache stays stale until the next main run.

Suggestion: store the granting `writer_branch` (or a grant reason) on the usage. A removal then revokes only uses whose branch is no longer allowed, and an addition doesn't need to revoke anything.

### 3. `commit: 'true'` on an unauthorized branch silently saves nothing

`infra/runner-cache/commit.go:11`

`AcceptsCommit("true")` only checks that the server echoed the mode back, not `CanPublish`. Explicitly asking for a save on a branch without a grant mounts the volume and discards the changes with no warning.

Scenario: in step 3 of the documented experiment, the grant is missing or misspelled (branch names must match exactly), or a concurrent policy edit revoked it. The seed job succeeds, nothing is saved, and the rerun is cold. The user can't tell a missing grant from a cache miss.

Suggestion: emit a `::warning::` when commit is `true` and `can_publish` is false.

## Smaller issues

### 4. Reordering branches counts as a change and revokes saves

`server/lib/tuist/runners/cache_volumes.ex:221`

`volume.writer_branches == branches` compares lists by order. Saving the same set in a different order is treated as a change and revokes every pending save on the volume, including main's. Compare as `MapSet`s or store a sorted list.

### 5. Wrong error message for authorization and not-found failures

`server/lib/tuist_web/live/runner_volumes_live.ex:139`

Every failure in the `with` chain falls into one `else`, so a failed authorization, a missing selected volume, or `:not_found` all show "Use up to 20 exact branch names." A user whose admin role was removed after mount is told to fix their branch list. Distinguish `:invalid_parameters` from the other failures.

### 6. Rejected commit mode leaves a usage row counted toward the pod limit

`infra/tart-kubelet/internal/podagent/custom_volumes.go:400`

When the agent rejects an identity for an unsupported commit mode, the server has already inserted a usage row. Rows that never attach still count toward the 8-per-pod limit in `ensure_job_capacity!`. With version skew, a job trying several keys with an explicit mode can hit `:capacity` for later keys. The rows also never show up in volume history, since they never report.

### 7. User docs include an internal experiment runbook

`server/priv/docs/en/guides/features/runners/cache-volumes.md:130`

The public guide has a five-step procedure built around Tuist's own CLI migration experiment (`cli-build-experiment`, `cli-swifterpm-experiment`, dependency-install timing). It belongs in the PR or the follow-up issue. The `commit` and writer-branch description alone covers the feature.

## Cleanups

### 8. Commit mode validated twice

`server/lib/tuist/runners/cache_volumes.ex:37`

The same `["auto", "true", "false"]` literal is checked in both `allocate/1` and `allocate_for_job/3`, and `allocate/1` calls `Map.get(params, "commit", "auto")` twice. Bind it once and keep a single check, or use a `@commit_modes` attribute.

### 9. Variadic `commit` parameter in the Go client

`infra/linux-runner-image/cmd/tuist-cache-volume/macos.go:28`

`acquireMac`, `acquireMacAt`, `acquire`, `attachWithClient` and `attachWithMounter` take `commit ...string`, plus a `requestedCommit` helper that pulls out the first element. This seems to exist only so existing test call sites compile unchanged. Production always passes one value. A plain `commit string` parameter makes the contract explicit and removes the helper.

### 10. Duplicated empty-to-`auto` helper

`infra/tart-kubelet/internal/podagent/custom_volumes.go:445`

`customVolumeCommit` (tart-kubelet) and `commitMode` (runners-controller) are identical. Both modules already import `infra/runner-cache`, which owns `AcceptsCommit`. Move a single `cachevolumes.CommitMode` there.
