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

By default, successful jobs on the repository's default branch save their changes
for future runs when triggered by these events:

| Provider | Events that save changes |
| --- | --- |
| GitHub Actions | Push, schedule, manual dispatch |
| Buildkite | Webhook, schedule |
| GitLab CI | Push, schedule, web |

Other jobs, including pull requests, merge requests and tags, can use the cache,
but their changes are discarded. With GitHub Actions, you can change which
branches save on the runner profile, for example to let pull requests or release
branches update the cache; see [Choose which branches save](#choose-which-branches-save).

Concurrent jobs work independently; changes from different jobs are not merged.
Never cache credentials or irreplaceable data.

### Choose which branches save {#choose-which-branches-save}

For GitHub Actions, you can change which branches save their changes. Open
**Runners → Profiles**, edit the profile your workflows use in `runs-on:`, and
expand **Save cache from**. The list applies to every custom volume used by jobs
on that profile, including volumes created later.

![The runner profile form with the Save cache from section expanded, listing main and release/* as branches that save their changes](/images/guides/features/runners/save-cache-from.png)

Until you change it, the list follows each repository's default branch. Add or
remove branches to replace it with up to 20 branch names. Use `*` as a wildcard:
`release/*` matches `release/1.0`, and `*` matches every branch. Successful push,
schedule and manual-dispatch jobs, and pull requests from the same repository,
save their changes when their branch matches. On push and manual-dispatch runs, a
tag with a matching name also matches. Removing every branch, or **Use default
branch**, returns to following the default branch.

Jobs on other branches can still use the cache, but their changes are discarded.
Fork pull requests and `pull_request_target` jobs never save. Changing the list
or deleting the profile discards pending changes the new list no longer allows;
a deleted profile falls back to the default branch. Buildkite and GitLab CI
always save from the default branch.

### Skip or request a save {#skip-or-request-a-save}

The GitHub action accepts `commit: auto` (the default), `commit: 'false'` (discard
this job's changes), and `commit: 'true'` (request a save). Both `auto` and `true`
remain subject to the profile's **Save cache from** list and successful job
completion; `true` cannot grant a branch permission or save a failed job. If the
job is not allowed to save when the volume is attached, the action emits a warning
and its changes are discarded.

## Capacity and retention {#capacity-and-retention}

Each volume holds up to **20 GB** and expires after **7 days without a job mount**.
The next job starts with an empty volume after expiry.

Saved contents can accumulate across runs. Volumes do not prune old dependencies:
use your tool's cleanup settings to keep them small. Writes to a full volume can
fail the job. When saved contents reach **80%** of the volume's capacity and a job
runs out of space on them, the next job starts with an empty volume and its
changes begin a new saved state.

## Inspecting and clearing volumes {#inspecting-and-clearing-volumes}

Open **Runners → Volumes** to inspect used space, cache hit rate and job history.
Account administrators can select **Clear volume** to make future jobs start
empty. Running jobs keep their private copies but cannot save them back.
