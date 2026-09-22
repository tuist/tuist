# Tuist cache volumes

Attach a private writable clone of the latest committed snapshot. Each key is
scoped to your account, repository, CPU architecture, and execution user. Jobs
on different hosts can reuse the same cache. Concurrent jobs have isolated
clones. No `id-token` permission or workflow credential is required.

After checkout and before Gradle (replace `main` with your reviewed commit):

```yaml
- uses: tuist/tuist/.github/actions/cache-volume@main
  with:
    key: gradle-caches
    path: ~/.gradle/caches
- uses: tuist/tuist/.github/actions/cache-volume@main
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
last use, and job history; delete a volume. Deletion
invalidates old clones immediately for publication and clears the saved head.
Running jobs finish with their private copies. Physical reclamation follows
teardown; unavailable agents remain pending. A future use of the key starts fresh.

The action is included in this repository; a standalone `tuist/cache-volume`
action is not yet published. Storage must be enabled by the Tuist operator.
