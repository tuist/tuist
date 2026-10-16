# Tuist Cache Volume

Attach a private writable clone of the latest committed snapshot. Each key is
scoped to your account, repository, CPU architecture, and execution user. Jobs
on different hosts can reuse the same cache. Concurrent jobs have isolated
clones. No `id-token` permission or workflow credential is required.

Attach after checkout and before Gradle populates its directories:

```yaml
- uses: tuist/cache-volume@v1
  with:
    key: gradle-caches
    path: ~/.gradle/caches
- uses: tuist/cache-volume@v1
  with:
    key: gradle-wrapper
    path: ~/.gradle/wrapper
- run: ./gradlew test
```

Keep existing runner labels and container images. Native and container jobs use
identical action inputs. Do not restore archive caches into these paths. If you
set `GRADLE_USER_HOME`, use paths beneath that location. Paths must be absent or
empty; the action never deletes existing content. The same key identifies the
same data even if the mount path changes. Do not attach the same key twice in
one job under different paths.

PRs consume warm snapshots and write
to their own clones; by default only successful default-branch push, manual, and scheduled
jobs publish. Failed jobs and disallowed writers are discarded. Publications
use last-publication-wins. Cache data is disposable and must not contain secrets.

Under **Runners → Volumes**, inspect cache hits, attachment times, retained size,
last use, and job history; clear a volume. Clearing
invalidates old clones immediately for publication and clears the saved head.
Running jobs finish with their private copies. Physical reclamation follows
teardown; unavailable agents remain pending. A future use of the key starts fresh.

## Inputs and output

| Name | Contract |
| --- | --- |
| `key` | Required stable name within the repository, architecture and execution user. Use a new key to start a separate cache. |
| `path` | Required absent or empty directory. Absolute paths, workspace-relative paths and `~/` are supported. |
| `commit` | Optional `auto`, `'true'`, or `'false'`; save intent never overrides the server writer policy. |
| `cache-hit` | Output string `true` for a mounted saved snapshot; `false` for a cold directory or unavailable storage. |

Use `id: dependencies` to access `${{ steps.dependencies.outputs.cache-hit }}`.
Continue running the dependency manager on hits: the volume may not contain every
dependency required by the current commit. The action attaches the volume;
the service saves eligible successful jobs after teardown. No post action or
additional workflow permissions are required.

A missing client fails with a Tuist Linux or macOS runner requirement. Unavailable
storage warns and falls back to a job-local directory. Invalid or nonempty paths
fail without replacing their contents. The default volume capacity is 20 GB.
When saved contents reach 80% of capacity and a job runs out of space on them,
the next job starts empty.
Linux and macOS fleets must have cache volumes enabled.

### Commit controls and cache saving

The GitHub action accepts `commit: auto` (the default), `commit: 'false'` (discard
this job's changes), and `commit: 'true'` (request a save). Both `auto` and `true`
remain subject to the runner profile's **Save cache from** list and successful job completion;
`true` cannot grant a branch permission or save a failed job. If the job lacks permission at attachment, the action emits a warning and its changes are discarded.

Account administrators configure **Save cache from** on each runner profile under
**Runners → Profiles**. The list applies to every custom volume attached by
GitHub Actions jobs that run on the profile, including volumes created later.
Until you change it, the list follows each repository's default branch.

Once you add or remove a branch, the list holds up to 20 branch names. `*`
matches any characters, so `release/*` covers `release/1.0` and `*` covers every
branch. Successful push, schedule and manual-dispatch jobs, and pull requests
from the same repository, save their changes when their branch matches. On push
and manual-dispatch runs, a tag with a matching name also matches. Removing every
branch, or **Use default branch**, returns to following the default branch.

Fork pull requests and `pull_request_target` never save. Buildkite, GitLab and
built-in macOS volume policies are unchanged. Changing the list or deleting the
profile revokes pending saves it no longer allows; a deleted profile falls back
to the default branch. Additions apply to new volume attachments.

Explicit `true`/`false` modes require updated runner clients, host agents and
server. The default `auto` action invocation remains compatible with older
clients. The transport requires explicit server/host acknowledgement of a new
mode before exposing the mounted cache, so an older component cannot silently
ignore `commit: 'false'`.

## Releases

The public installation is `tuist/cache-volume@v1`; pin an immutable release
commit when stronger reproducibility is needed. `v1.x.y` tags are immutable;
`v1` automatically follows the latest release in that major version. The
`SOURCE_COMMIT` file records the monorepo source.

The monorepo's **Cache Volume Integrations** workflow tests and packages pull
requests. Relevant changes merged to `main` automatically release the GitHub
action, Buildkite plugin and GitLab template together. The existing
`release:check` / git-cliff machinery derives their shared semantic version;
there is no version to enter or routine manual dispatch. A no-input dispatch
recovers incomplete releases from their original published `SOURCE_COMMIT`,
even after `main` advances. Later changes are released in a follow-up run.
See the monorepo's
[release implementation](https://github.com/tuist/tuist/tree/main/ci/cache-volume).

Distribution repositories need a `main` branch and write access for
`TUIST_RELEASE_GITHUB_TOKEN` as a one-time setup. Publishing the wrappers does
not enable cache volumes on the fleet; storage rollout is independent.

On Linux, paths are mounted as ordinary directories, so tools can use their usual locations
such as `deps`, `_build`, and `node_modules`. Keep your normal `.gitignore` rules.
Each action call attaches one directory; use a different key for each directory.

On macOS, targets are attached as symlinks. Cache download directories such as `~/.npm`
or `~/.gradle/caches`; `node_modules` is rejected because npm replaces symlinks.
Other tools that replace their cache directory are also incompatible. For a
workspace path, ignore the link without a trailing slash (for example `.gradle`,
not `.gradle/`, in `.gitignore`). Paths must be a single line without control
characters; use a plain YAML string instead of `path: |`.

On macOS, use a macOS runner profile. Native jobs are supported; Linux container
examples do not apply to macOS. Volumes mount in the macOS guest, so a separate
Docker VM does not inherit them. Built-in Tuist and Xcode caches stay automatic;
custom volumes use separate empty directories and platform-specific identities.
