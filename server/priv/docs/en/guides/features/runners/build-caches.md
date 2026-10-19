---
{
  "title": "Xcode and module caches",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Keep the Xcode compilation cache and the Tuist module cache between jobs on Tuist macOS runners with GitHub Actions, Buildkite, and GitLab CI."
}
---
# Xcode and module caches {#xcode-and-module-caches}

Tuist macOS runners can keep two caches between jobs, so a fresh runner starts
warm:

- **Xcode cache**: the store of Xcode's compilation cache. Builds that have
  compilation caching turned on replay compiled outputs from it instead of
  compiling or downloading them again.
- **Module cache**: Tuist's local cache, with
  <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link>
  binaries, compiled manifests, plugins and selective testing results.

Add a step for each cache a job should use, after checkout and before any
`tuist` or `xcodebuild` command. A job without the step still works, but starts
with empty local caches and fetches everything from Tuist's remote cache or
builds it again.

The steps only decide where the caches live. They don't replace your existing
cache setup: keep running `tuist setup cache`, or the build settings that turn
compilation caching on, as described in the
<.localized_link href="/guides/features/cache/xcode-cache">Xcode cache guide</.localized_link>,
and keep authenticating for the module cache as usual.

## GitHub Actions {#github-actions}

Add `tuist/xcode-cache@v1` and `tuist/module-cache@v1` to the job:

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

A project that doesn't use Tuist only needs the Xcode cache:

```yaml
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

## Buildkite {#buildkite}

Add the plugins to a step on your Tuist macOS queue. They run after checkout,
before the command:

```yaml
steps:
  - label: Test
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
```

## GitLab CI {#gitlab-ci}

Include the templates and reference their snippets in `before_script`:

```yaml
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
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
```

Use `!reference` rather than `extends`, which replaces `before_script` and so
cannot combine the two snippets with your own commands.

> [!NOTE]
> GitLab CI jobs don't save these caches yet. Each job starts with empty caches
> and keeps them for the rest of the job. Once saving is available for GitLab
> CI, the same snippets start saving without pipeline changes.

## Xcode build settings {#xcode-build-settings}

The Xcode cache step sets `XCODE_XCCONFIG_FILE` to a file that sets the store's
location and size limit, which every later `xcodebuild` in the job uses. If the
job already sets `XCODE_XCCONFIG_FILE` before the step, that file is included
last, so its settings win. Setting `XCODE_XCCONFIG_FILE` after the step replaces
the runner's file, and the store stays on the runner's own disk.

## Saving changes {#saving-changes}

Successful jobs from your own repository save their changes for future jobs.
Jobs from forks start with empty caches and never save. Failed and cancelled
jobs, and jobs that use neither cache, don't save.

| Provider | Jobs that save changes |
| --- | --- |
| GitHub Actions | Successful jobs from the repository itself, including its pull requests |
| Buildkite | Successful builds from the pipeline's own repository |
| GitLab CI | None yet |

Concurrent jobs work independently, and their changes are not merged. The
**Save cache from** setting on runner profiles applies only to
<.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link>, not to these caches.

## Capacity {#capacity}

The two caches share storage that Tuist sizes and prunes for you: the Tuist
CLI evicts the least recently used module cache binaries, and the Xcode cache
store is kept within its own limit. There is nothing to configure or clear, and
neither cache counts against the capacity of your
<.localized_link href="/guides/features/runners/cache-volumes">cache volumes</.localized_link>, which stay separate.

Some accounts still get both caches in every job automatically. There, the
steps change nothing, so you can add them to your workflows now.

## Other runners {#other-runners}

On runners that are not Tuist macOS runners, the steps do nothing, so the same
workflow runs anywhere. If a runner could not restore the caches, the step logs
a warning and the job continues with empty ones. A cache problem never fails
the job.
