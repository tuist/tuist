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

Add the steps after checkout and before the commands that use the caches. On
runners that are not Tuist runners they do nothing, and a cache problem never
fails the job: the step logs a warning and the job continues with an empty
cache.

## Managed caches {#managed-caches}

The steps only decide where the caches live. Keep your existing cache setup:
`tuist setup cache` or the build settings that turn compilation caching on (see
the <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache guide</.localized_link>),
authentication for the module cache, and the
<.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle plugin</.localized_link> for Gradle's remote build cache.
In GitLab CI, combine snippets with `!reference`, because `extends` replaces
`before_script`.

Some accounts still get the Xcode and module caches in every macOS job
automatically. There, those two steps change nothing, so you can add them now.

### Xcode cache {#xcode-cache}

Keeps the store of Xcode's compilation cache on macOS runners.

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [Buildkite]
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```
<!-- -->
:::

### Module cache {#module-cache}

Keeps Tuist's local cache on macOS runners:
<.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> binaries, compiled manifests, plugins and selective testing results.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-macos
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - run: tuist auth login
      - run: tuist install
      - run: tuist generate --no-open
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist install
      tuist generate --no-open
      tuist test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist install
    - tuist generate --no-open
    - tuist test
```
<!-- -->
:::

### Gradle cache {#gradle-cache}

Keeps the `caches` and `wrapper` directories of Gradle's user home on Linux and
macOS runners: dependencies, transformed jars, compiled build scripts and
Gradle distributions. Set `GRADLE_USER_HOME` before the step if you use one,
and turn off other caching of those directories, such as `cache: gradle` on
`actions/setup-java`.

::: code-group

```yaml [GitHub Actions]
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

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```
<!-- -->
:::

## Custom volumes {#custom-volumes}

Choose a stable `key` and a `path`, then attach the volume before installing
dependencies. The path must be empty or absent. Remove any archive cache or
artifact restore that writes to the same directory. To keep several directories
in one volume, see
[Several directories in one volume](#several-directories-in-one-volume).

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: |
      npm ci
      npm test
```

```yaml [GitLab CI]
test:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - npm ci
    - npm test
```
<!-- -->
:::

### Several directories in one volume {#several-directories-in-one-volume}

A volume can hold several directories. In GitHub Actions, list one path per
line; in Buildkite, set `path` to a list; in GitLab CI, pass `--path` once per
directory. Blank lines and surrounding whitespace are ignored.

::: code-group

```yaml [GitHub Actions]
jobs:
  lint:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: python-tools
          path: |
            ~/.cache/pip
            ~/.cache/pre-commit
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

```yaml [Buildkite]
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: |
      pip install pre-commit
      pre-commit run --all-files
```

```yaml [GitLab CI]
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```
<!-- -->
:::

- **Shared capacity.** All paths share the volume's 20 GB capacity and are
  restored and saved together.
- **Group small, related directories.** Give a large or fast-changing directory
  its own volume.
- **No nesting.** Paths in one volume must not contain each other.
- **Changing the list starts cold.** Each path is stored in its own directory
  inside the volume, identified by how the path is written. Switching between
  one path and several, or adding, removing or rewriting a path, changes that
  layout: the first job after the change starts cold for the affected paths.
  Content of paths that are no longer listed stays in the volume until you
  clear it.

### How keys work {#how-keys-work}

A key names a volume that changes over time; it is not the name of a fixed
snapshot like an `actions/cache` key.

- **One volume per key.** Each key is scoped to the repository (on Buildkite,
  the pipeline; on GitLab CI, the project), platform, CPU architecture and user.
  Every job that attaches it starts from the latest saved contents, and eligible
  jobs save their changes back to the same volume.
- **Keep keys stable.** Don't put versions or lockfile hashes in a key. With
  `actions/cache`, a key like `deps-${{ hashFiles('Package.resolved') }}`
  creates a new entry for each change, and `restore-keys` falls back to an older
  one. Here, a new key is a new, empty volume: the first job after every change
  starts cold, and the old volumes stay around until they expire. Keep the key
  and let your tool update the contents; package managers reuse whatever is
  still valid.
- **No partial matches.** There are no restore keys. A key that hasn't been
  saved yet starts empty.
- **Start over on purpose.** Change the key, or clear the volume in the
  dashboard, when you want a job to start empty.
- **Leave `tuist-` keys to Tuist.** The managed caches use keys that start
  with `tuist-`, so pick a different name for your own volumes.

On Linux, paths are mounted as ordinary directories, so tools can use their usual locations
such as `deps`, `_build`, and `node_modules`. Keep your normal `.gitignore` rules.
On macOS, paths are symlinks: use download caches such as `~/.npm`;
`node_modules` and tools that replace their cache directory
are unsupported. Ignore workspace links without a trailing slash in `.gitignore`.

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

The Xcode and module caches share storage that Tuist sizes and prunes for you,
and they don't count against the capacity of the volumes below.

The Gradle cache and each custom volume hold up to **20 GB** and expire after
**7 days without a job mount**. The next job starts with an empty volume after
expiry. The Gradle cache step has Gradle remove entries unused for seven days
after every build.

Custom volumes do not prune old dependencies: use your tool's cleanup settings
to keep them small. Writes to a full volume can fail the job. When saved
contents reach **80%** of the volume's capacity and a job runs out of space on
them, the next job starts with an empty volume and its changes begin a new
saved state.

## Inspecting and clearing volumes {#inspecting-and-clearing-volumes}

Open **Runners → Volumes** to inspect used space, cache hit rate and job history.
Account administrators can select **Clear volume** to make future jobs start
empty. Running jobs keep their private copies but cannot save them back. The
Xcode and module caches appear there too, but can't be cleared.
