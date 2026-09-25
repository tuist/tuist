---
{
  "title": "Cache volumes",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Persist dependency directories between Tuist Linux or macOS runner jobs with cache volumes for GitHub Actions, Buildkite, and GitLab CI."
}
---
# Cache volumes {#cache-volumes}

Cache volumes persist dependency directories between jobs on Tuist Linux or macOS runners.
Each job gets a private writable copy of the latest saved contents.

Choose a stable `key` and a `path`, then attach the volume before installing
dependencies. The path must be empty or absent. Remove any archive cache or
artifact restore that writes to the same directory.


Targets are attached as symlinks. Cache download directories such as `~/.npm`
or `~/.gradle/caches`; `node_modules` is rejected because npm replaces symlinks.
Other tools that replace their cache directory are also incompatible. For a
workspace path, ignore the link without a trailing slash (for example `.gradle`,
not `.gradle/`, in `.gitignore`). Paths must be a single line without control
characters; use a plain YAML string instead of `path: |`.

## GitHub Actions {#github-actions}

Add `tuist/cache-volume@v1` before your build step:

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

The action exposes a `cache-hit` output and also works in ordinary GitHub Actions
container jobs, without privileged mode or extra workflow permissions. Native
jobs and containers running as different users have separate volumes.

## Buildkite {#buildkite}

Add the plugin to a step on your Tuist Linux or macOS queue. It attaches after checkout,
before the command runs:

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

## GitLab CI {#gitlab-ci}

Call the installed client in `before_script`:

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

For macOS, select your macOS runner profile in the examples above. All three
providers support native macOS commands; GitLab uses the shell executor.
GitHub container jobs and Docker actions require Linux. macOS custom volumes
are APFS images mounted in the macOS guest and are not automatically shared
with a separate Docker VM.

Built-in Tuist and Xcode compilation caches continue working automatically.
Custom volumes are additional opt-in caches; use a separate empty directory
and do not target the built-in cache mount. Linux and macOS volumes with the
same key are separate.

## Saving changes {#saving-changes}

Successful jobs on the default branch save their changes for future runs when
triggered by these events:

| Provider | Events that save changes |
| --- | --- |
| GitHub Actions | Push, schedule, manual dispatch |
| Buildkite | Webhook, schedule |
| GitLab CI | Push, schedule, web |

Other jobs, including pull requests, merge requests and tags, can use the cache,
but their changes are discarded. Concurrent jobs work independently; changes
from different jobs are not merged. Never cache credentials or irreplaceable data.

## Capacity and retention {#capacity-and-retention}

Each volume holds up to **20 GB** and expires after **7 days without a job mount**.
The next job starts with an empty volume after expiry.

Saved contents can accumulate across runs. Volumes do not prune old dependencies:
use your tool's cleanup settings or clear the volume before it fills up. Writes
to a full volume can fail the job.

## Inspecting and clearing volumes {#inspecting-and-clearing-volumes}

Open **Runners → Volumes** to inspect used space, cache hit rate and job history.
Account administrators can select **Clear volume** to make future jobs start
empty. Running jobs keep their private copies but cannot save them back.
