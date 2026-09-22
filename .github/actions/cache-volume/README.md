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
to their own clones; only successful default-branch push, manual, and scheduled
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
| `cache-hit` | Output string `true` for a mounted saved snapshot; `false` for a cold directory or unavailable storage. |

Use `id: dependencies` to access `${{ steps.dependencies.outputs.cache-hit }}`.
Continue running the dependency manager on hits: the volume may not contain every
dependency required by the current commit. The action attaches the volume;
the service saves eligible successful jobs after teardown. No post action or
additional workflow permissions are required.

A missing client fails with a Tuist Linux runner requirement. Unavailable
storage warns and falls back to a job-local directory. Invalid or nonempty paths
fail without replacing their contents. The default volume capacity is 20 GB.
Linux only; the fleet must have cache volumes enabled.

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
is available for recovery. See the monorepo's
[release implementation](https://github.com/tuist/tuist/tree/main/ci/cache-volume).

Distribution repositories need a `main` branch and write access for
`TUIST_RELEASE_GITHUB_TOKEN` as a one-time setup. Publishing the wrappers does
not enable cache volumes on the fleet; storage rollout is independent.
Until the first release is published, test with
`tuist/tuist/.github/actions/cache-volume@<reviewed-commit>`.
