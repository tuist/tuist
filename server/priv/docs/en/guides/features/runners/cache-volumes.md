---
{
  "title": "Cache volumes",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Persist dependency directories between Tuist Linux runner jobs with cache volumes for GitHub Actions, Buildkite, and GitLab CI."
}
---
# Cache volumes {#cache-volumes}

Cache volumes keep dependency directories available between jobs on Tuist Linux
runners. Choose a stable key and a directory to retain, then attach the volume
before your tools populate that directory. Each job gets a private writable copy
of the latest saved contents, so concurrent jobs work independently.

Use volumes with native GitHub Actions jobs, GitHub Actions container jobs,
Buildkite commands, or GitLab shell jobs. Custom volumes currently support Linux;
macOS support will follow separately.

## GitHub Actions {#github-actions}

Use `tuist/cache-volume@v1` before the step that downloads or builds dependencies:

```yaml
permissions:
  contents: read

jobs:
  test:
    runs-on: tuist-linux
    env:
      GRADLE_USER_HOME: ${{ github.workspace }}/.gradle
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/cache-volume@v1
        with:
          key: gradle-dependencies-v1
          path: .gradle
      - run: ./gradlew test
```

Pin the action to a reviewed commit in production. Attach before another step
writes to that directory; nonempty paths are never replaced. The action supports
absolute, relative and `~/` paths and exposes a `cache-hit` output. No additional
workflow permissions or privileged container options are required. Avoid
restoring an archive into the same directory.

Successful default-branch push, scheduled and manual jobs publish
cache updates after teardown. PRs read the shared cache but their changes are
discarded. If jobs start from the same saved version, the first accepted
publication saves its changes; other jobs cannot overwrite that newer version.
Changes are not merged. Volumes are scoped by account,
repository, key, architecture and execution UID. Root containers and non-root
native jobs have separate volumes. The action also works in ordinary GitHub
Actions container jobs; set `container` to the image your job needs.

## Buildkite {#buildkite}

Use the `tuist/cache-volume#v1` plugin on a Tuist Linux queue:

```yaml
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: gradle-dependencies
              path: .gradle
    env:
      GRADLE_USER_HOME: .gradle
    command: ./gradlew test
```

The plugin attaches after checkout and before the command. Pin a reviewed plugin
commit in production. Successful default-branch webhook and scheduled builds
without a PR or tag can save changes. Manual/API builds and other branches can
read but cannot save. Volumes are scoped to the Buildkite organization, pipeline,
and repository, in addition to account, key, architecture and execution UID.
Renaming a pipeline preserves its volumes; changing its repository URL starts
a new cache.

## GitLab CI {#gitlab-ci}

Call the installed client before dependency installation:

```yaml
test:
  tags: [tuist-linux]
  variables:
    GRADLE_USER_HOME: "$CI_PROJECT_DIR/.gradle"
  before_script:
    - tuist-cache-volume --key gradle-dependencies --path .gradle
  script:
    - ./gradlew test
```

A [reusable include](https://github.com/tuist/tuist/tree/main/ci/cache-volume/gitlab)
is also available to vendor into your project or include at a reviewed commit.
It composes with existing setup commands through GitLab's `!reference`.
Each GitLab instance and project has a separate cache namespace. Project
renames preserve volumes. Successful default-branch push, schedule and web
pipelines can save; merge requests, tags, child and other pipelines cannot.
The instance must permit the acquired job token to read its own job and the
repository's branches. Missing source metadata never grants save permission.

GitLab's `cache:` archives and artifacts restore before `before_script`.
Remove overlapping paths before switching them to volumes, and keep unrelated
archive caches as they are.

Buildkite and GitLab integrations target native commands on Tuist Linux runners.
GitLab uses the shell executor; specifying `image:` does not switch executors.
Docker child containers need explicit private cache-root mounts and separate
validation.

## Inspecting and clearing volumes {#inspecting-and-clearing-volumes}

Open **Runners → Volumes** to see account-wide used space and cache hit rate,
with charts and comparisons for the selected period. Search and sort volumes
by name, repository, used space, capacity or last use. Each volume shows its
repository, platform, last use and capacity, plus storage charts, hit rate,
job runs and paginated job history with job and workflow names.
Storage totals include copies awaiting deletion and identify missing measurements.
They sum logical filesystem usage across copies, which can count shared data
multiple times; they do not represent billable storage or unique physical bytes.
Account administrators can clear a volume. Clearing makes subsequent jobs start cold;
running jobs finish with their private copies, which cannot republish deleted
data. Physical storage removal waits for agents to confirm it.

## Capacity and retention {#capacity-and-retention}

Each volume has a **20 GB** capacity. Saving updates retains the current directory
contents, including files accumulated by earlier runs. Volumes do not automatically
prune old dependencies; use your tool's cleanup settings or clear the volume when
needed. Filling a volume can cause writes, and consequently the job, to fail.

Volumes are automatically evicted after **7 days of inactivity**. Each successful
job mount updates **Last used** and starts a new seven-day window. Allocation
attempts and background storage reports do not extend it. A volume used at least
once within each seven-day window remains available. After seven consecutive
days without a mount, its cache is invalidated and queued for physical deletion;
the next job starts with an empty volume. Cleanup is checked every five minutes,
and actual removal waits for running jobs and storage-agent acknowledgement.

Unavailable storage falls back to empty job-local directories before attachment; storage failures after
attachment can fail a build. Cache data is disposable, and workflows admitted to
the repository can read it, including forks. Never cache credentials or
irreplaceable state. This is separate from Tuist's Gradle build-task output cache.
