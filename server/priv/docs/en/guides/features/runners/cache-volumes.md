---
{
  "title": "Cache volumes",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Keep the Xcode, module and Gradle caches and any other directory between Tuist Linux or macOS runner jobs with GitHub Actions, Buildkite, and GitLab CI."
}
---
# Cache volumes {#cache-volumes}

Tuist runners can keep caches between jobs, so a fresh runner starts warm.
Each job gets a private writable copy of the latest saved contents.

- **Managed caches** keep the Xcode compilation cache, Tuist's module cache and
  Gradle's caches with one step each. Tuist knows where each cache lives and
  keeps it within its storage.
- **Custom volumes** keep any other directory, such as a package manager's
  download cache, under a key you choose.

Add the steps after checkout and before the commands that use the caches. A
job without them still works, but starts with empty local caches.

## Managed caches {#managed-caches}

- **Xcode cache** (macOS): the store of Xcode's compilation cache.
- **Module cache** (macOS): Tuist's local cache, with
  <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> binaries, compiled manifests, plugins and selective testing results.
- **Gradle cache** (Linux and macOS): `$GRADLE_USER_HOME/caches` and
  `$GRADLE_USER_HOME/wrapper`, with dependencies, transformed jars, compiled
  build scripts and Gradle distributions.

| Cache | GitHub Actions | Buildkite | GitLab CI |
| --- | --- | --- | --- |
| Xcode | `tuist/xcode-cache@v1` | `tuist/xcode-cache#v1` | `.tuist-xcode-cache` |
| Module | `tuist/module-cache@v1` | `tuist/module-cache#v1` | `.tuist-module-cache` |
| Gradle | `tuist/gradle-cache@v1` | `tuist/gradle-cache#v1` | `.tuist-gradle-cache` |

The steps only decide where the caches live. Keep your existing cache setup:
`tuist setup cache` or the build settings that turn compilation caching on (see
the <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache guide</.localized_link>),
authentication for the module cache, and the
<.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle plugin</.localized_link> for Gradle's remote build cache.

On runners that are not Tuist runners, the steps do nothing, so the same
workflow runs anywhere. If a runner could not restore a cache, the step logs a
warning and the job continues with an empty one. A cache problem never fails
the job.

Some accounts still get the Xcode and module caches in every macOS job
automatically. There, those two steps change nothing, so you can add them to
your workflows now.

### Xcode build settings {#xcode-build-settings}

The Xcode cache step sets `XCODE_XCCONFIG_FILE` to a file that sets the store's
location and size limit, which every later `xcodebuild` in the job uses. If the
job already sets `XCODE_XCCONFIG_FILE` before the step, that file is included
last, so its settings win. Setting `XCODE_XCCONFIG_FILE` after the step replaces
the runner's file, and the store stays on the runner's own disk.

### Gradle {#gradle}

Set `GRADLE_USER_HOME` before the Gradle cache step if you use one. Its `caches`
and `wrapper` directories must be empty when the step runs, so turn off other
caches of them, such as `cache: gradle` on `actions/setup-java`, the caching of
`gradle/actions/setup-gradle`, or GitLab `cache:paths`.

Gradle cleans its cache only when its daemon stops, which a CI job rarely
reaches. The step installs an init script in `$GRADLE_USER_HOME/init.d` that
cleans after every build and removes entries unused for seven days, so the
cache stays within its volume.

## Custom volumes {#custom-volumes}

Choose a stable `key` and a `path`, then attach the volume before installing
dependencies. The path must be empty or absent. Remove any archive cache or
artifact restore that writes to the same directory. Use the managed caches
above for the Xcode, module and Gradle caches instead of a custom volume.

On Linux, paths are mounted as ordinary directories, so tools can use their usual locations
such as `deps`, `_build`, and `node_modules`. Keep your normal `.gitignore` rules.
On macOS, paths are symlinks: use download caches such as `~/.npm`;
`node_modules` and tools that replace their cache directory
are unsupported. Ignore workspace links without a trailing slash in `.gitignore`.
Each action call attaches one directory; use a different key for each directory.

## GitHub Actions {#github-actions}

A macOS job with the Xcode and module caches:

```yaml
permissions:
  contents: read
  id-token: write

jobs:
  test:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist auth login
      - run: tuist setup cache
      - run: tuist generate --no-open
      - run: tuist test
```

A Gradle job:

```yaml
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/gradle-cache@v1
      - run: ./gradlew test
```

A custom volume, added with `tuist/cache-volume@v1`:

```yaml
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm-v1
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

`tuist/cache-volume` and `tuist/gradle-cache` expose a `cache-hit` output.
`tuist/cache-volume` also works in ordinary GitHub Actions container jobs,
without privileged mode or extra workflow permissions. Native jobs and
containers running as different users have separate volumes.

## Buildkite {#buildkite}

Add the plugins to a step on your Tuist Linux or macOS queue. They run after
checkout, before the command:

```yaml
steps:
  - label: iOS
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist setup cache
      tuist install
      tuist generate --no-open
      tuist test

  - label: Android
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: ./gradlew test
```

## GitLab CI {#gitlab-ci}

Include the templates and reference their snippets in `before_script`. Call the
installed `tuist-cache-volume` client for custom volumes:

```yaml
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

ios:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist setup cache
    - tuist install
    - tuist generate --no-open
    - tuist test

android:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - ./gradlew test
```

Use `!reference` rather than `extends`, which replaces `before_script` and so
cannot combine the snippets with each other or with your own commands.

All three providers support native macOS commands; GitLab uses the shell executor.
GitHub container jobs and Docker actions require Linux. macOS volumes are APFS
images mounted in the macOS guest and are not automatically shared with a
separate Docker VM. Linux and macOS volumes with the same key are separate.

## Saving changes {#saving-changes}

The Xcode and module caches save the changes of successful jobs from your own
repository. Jobs from forks start with empty caches and never save, and neither
do failed or cancelled jobs or jobs that use neither cache.

| Provider | Xcode and module caches |
| --- | --- |
| GitHub Actions | Successful jobs from the repository itself, including its pull requests |
| Buildkite | Successful builds from the pipeline's own repository |
| GitLab CI | Not saved yet: each job starts with empty caches |

The Gradle cache and custom volumes save the changes of successful jobs on the
repository's default branch when triggered by these events:

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

For GitHub Actions, you can change which branches save the Gradle cache and
custom volumes. Open **Runners → Profiles**, edit the profile your workflows use
in `runs-on:`, and expand **Save cache from**. The settings apply to every
volume used by jobs on that profile, including volumes created later. They don't
apply to the Xcode and module caches.

![The runner profile form with the Save cache from section expanded, with Default branch turned on and develop and release/* added as additional branches](/images/guides/features/runners/save-cache-from.png)

**Default branch** is on by default, so jobs on each repository's default branch
save their changes. Turn it off to save only from the additional branches.

Under **Additional branches**, add up to 20 branch names that also save. Use `*`
as a wildcard: `release/*` matches `release/1.0`, and `*` matches every branch.
Successful push, schedule and manual-dispatch jobs, and pull requests from the
same repository, save their changes when their branch matches. On push and
manual-dispatch runs, a tag with a matching name also matches.

Jobs on other branches can still use the cache, but their changes are discarded.
Fork pull requests and `pull_request_target` jobs never save. Narrowing these
settings or deleting the profile discards pending changes they no longer allow;
a deleted profile falls back to the default branch. Buildkite and GitLab CI
always save from the default branch.

## Capacity and retention {#capacity-and-retention}

The Xcode and module caches share storage that Tuist sizes and prunes for you:
the Tuist CLI evicts the least recently used module cache binaries, and the
Xcode cache store is kept within its own limit. There is nothing to configure,
and they don't count against the capacity of the volumes below.

The Gradle cache and each custom volume hold up to **20 GB** and expire after
**7 days without a job mount**. The next job starts with an empty volume after
expiry.

Saved contents can accumulate across runs. Custom volumes do not prune old
dependencies: use your tool's cleanup settings to keep them small. Writes to a
full volume can fail the job. When saved contents reach **80%** of the volume's
capacity and a job runs out of space on them, the next job starts with an empty
volume and its changes begin a new saved state.

## Inspecting and clearing volumes {#inspecting-and-clearing-volumes}

Open **Runners → Volumes** to inspect used space, cache hit rate and job history.
Account administrators can select **Clear volume** to make future jobs start
empty. Running jobs keep their private copies but cannot save them back. The
Xcode and module caches appear there too, but can't be cleared.
