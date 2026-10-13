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

On Linux, paths are mounted as ordinary directories, so tools can use their usual locations
such as `deps`, `_build`, and `node_modules`. Keep your normal `.gitignore` rules.
On macOS, paths are symlinks: use download caches such as `~/.npm` or
`~/.gradle/caches`; `node_modules` and tools that replace their cache directory
are unsupported. Ignore workspace links without a trailing slash in `.gitignore`.
Each action call attaches one directory; use a different key for each directory.

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

By default, successful jobs on the default branch save their changes for future runs when
triggered by these events:

| Provider | Events that save changes |
| --- | --- |
| GitHub Actions | Push, schedule, manual dispatch |
| Buildkite | Webhook, schedule |
| GitLab CI | Push, schedule, web |

Without an additional writer-branch grant, other jobs, including pull requests, merge requests and tags, can use the cache,
but their changes are discarded. Concurrent jobs work independently; changes
from different jobs are not merged. Never cache credentials or irreplaceable data.

### Commit controls and writer branches

The GitHub action accepts `commit: auto` (the default), `commit: 'false'` (discard
this job's changes), and `commit: 'true'` (request a save). Both `auto` and `true`
remain subject to the server's writer policy and successful job completion;
`true` cannot grant a branch permission or save a failed job.

Account administrators can open a GitHub custom volume under **Runners → Volumes**
and edit **Writer branches**. Default-branch publishing remains enabled. Up to
20 additional exact branch names can publish from same-repository push, schedule,
manual-dispatch and verified pull-request runs. Fork PRs and `pull_request_target`
cannot publish. Wildcards are not supported. Buildkite, GitLab and built-in macOS
volume policies are unchanged. Saving a changed policy revokes pending saves from
running jobs; permissions added by the change apply only to new volume attachments.

For a cold/warm experiment before merging a workflow:

1. Attach dedicated keys, such as `cli-build-experiment` and
   `cli-swifterpm-experiment`. The first branch job creates the volume records.
2. Add the exact test branch to **Writer branches** on both volumes.
3. Run the branch workflow with `commit: 'true'` on both attachment steps. Wait
   for a successful job and for both saved snapshots to appear in volume history.
4. Rerun with the same keys, toolchain and dependency inputs. Require both cache
   hits and record dependency-install time separately from queue/attachment time.
5. Remove the test branch from the policy and clear the experimental volumes
   when finished. Production cache keys are unaffected.

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
