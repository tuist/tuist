---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Use Docker on Tuist Runners: build and run containers, container jobs, service containers, and private registries."
}
---
# Docker {#docker}

Linux runners come with Docker ready to use. Each job gets its own Docker daemon inside the job's virtual machine, and the `docker` CLI, Buildx, and Compose are preinstalled. You don't need a setup action, and you don't need `sudo`.

```yaml
jobs:
  build:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t my-app .
      - run: docker run --rm my-app ./run-checks.sh
```

> [!NOTE]
> **Linux only**
>
> macOS runners don't provide a Docker daemon. Use a Linux <.localized_link href="/guides/features/runners/profiles">profile</.localized_link> for jobs that need one.

## Running a job in a container {#running-a-job-in-a-container}

Point `container` at the image your job should run in. Tuist pulls it and runs every step inside it:

```yaml
jobs:
  test:
    runs-on: tuist-linux
    container:
      image: ghcr.io/my-org/android-ci:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - run: ./gradlew test
```

## Service containers {#service-containers}

`services` works the same way it does on GitHub-hosted runners. Services are reachable on `localhost` at their mapped ports:

```yaml
jobs:
  test:
    runs-on: tuist-linux
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v4
      - run: mix test
```

## Private registries {#private-registries}

Authenticate with the registry's own login action, or `docker login`, before pulling or pushing:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

For a job-level `container`, pass the same credentials through the `credentials` key instead, as in the example above.

## Image pulls {#image-pulls}

Docker Hub pulls are served through a pull-through cache that Tuist operates, so jobs don't consume Docker Hub's anonymous rate limit. Images from other registries are pulled directly.

Every job starts with an empty image store, so an image your workflow uses is pulled once per job rather than reused across jobs. If a job pulls a large custom image, keep the image small, or build it in the workflow with a cached Buildx builder:

```yaml
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v6
        with:
          context: .
          tags: my-app:latest
          load: true
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

## Persistent dependency directories (opt-in) {#persistent-dependency-directories}

On fleets with Linux cache volumes enabled, attach a persistent directory with a
key and a path. Each job gets a private writable copy of the latest published
cache, including concurrent jobs and pull requests.

```yaml
permissions:
  contents: read

jobs:
  test:
    runs-on: tuist-linux
    container: eclipse-temurin:21-jdk
    env:
      GRADLE_USER_HOME: ${{ github.workspace }}/.gradle
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/tuist/.github/actions/cache-volume@main
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
discarded. Simultaneous successful writers publish independently; the last
publication wins without merging their changes. Volumes are scoped by account,
repository, key, architecture and execution UID. Root containers and non-root
native jobs have separate volumes.

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

Volumes are automatically evicted after **7 days of inactivity**. Each successful
job mount updates **Last used** and starts a new seven-day window. Allocation
attempts and background storage reports do not extend it. A volume used at least
once within each seven-day window remains available. After seven consecutive
days without a mount, its cache is invalidated and queued for physical deletion;
the next job starts with an empty volume. Cleanup is checked every five minutes,
and actual removal waits for running jobs and storage-agent acknowledgement.

Unavailable storage falls
back to empty job-local directories before attachment; storage failures after
attachment can fail a build. Cache data is disposable, and workflows admitted to
the repository can read it, including forks. Never cache credentials or
irreplaceable state. This is separate from Tuist's Gradle build-task output cache.

### Buildkite

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

### GitLab CI

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

Both integrations initially target native commands on Tuist Linux runners.
GitLab uses the shell executor; specifying `image:` does not switch executors.
Docker child containers need explicit private cache-root mounts and separate
validation. Public action/plugin releases accompany the enabled-fleet rollout.
