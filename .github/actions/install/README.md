# Tuist install

Install generated-project dependencies with automatic caching on macOS and Linux
GitHub Actions runners. The action retains the package's `.build` directory using
Tuist volumes when their client is available, or GitHub's archive cache otherwise.
It always runs `tuist install` with forced resolved versions and a nested dependency
cache, including on cache hits. There is no cache-mode input.

## Usage

The intended standalone entry point is `tuist/install@v1`. Until the first
release is published, use this action from a checkout of its monorepo source at
`.github/actions/install`, or pin `tuist/tuist/.github/actions/install@<commit>`.

After publication:

```yaml
jobs:
  generate:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist generate --no-open
```

Pin Tuist in your project's `mise.toml`. The action uses that installed CLI and
requires **4.214.0-canary.36 or newer**. Install tools and configure any private
package authentication before this step, without running `tuist install` from
setup hooks first. Commit `Package.resolved`. The same action works with
`runs-on: tuist-macos`, GitHub-hosted macOS runners, and Linux runners with the
required CLI and Swift toolchain installed.

| Input | Default | Behavior |
| --- | --- | --- |
| `path` | `.` | Project directory inside `GITHUB_WORKSPACE`, relative to it or absolute. Subdirectories follow Tuist's root lookup. |
| `cache-key` | Generated | Override the cache namespace to share a compatible workspace between jobs, or rotate it. |

The action follows Tuist's root markers (`Tuist/`, `Tuist.swift`, `tuist.toml`,
`Plugin.swift`, or `.git/`) and prefers `Tuist/Package.swift` over a root
`Package.swift`. For a standalone project without a root marker, `path` must
contain `Package.swift`. It retains `.build` beside the selected package.

The default key hashes the job name, actual Swift/Xcode toolchain versions,
checkout-relative package location, and `Package.swift` contents, with a layout
version prefix. It excludes the lockfile, branch, run ID, and absolute checkout
path. Volume storage also scopes keys by repository, account, platform,
architecture, and execution user. Keep the default key unless jobs intentionally
share compatible workspace state. GitHub archive keys additionally include OS,
architecture, and a lockfile hash; the restore prefix omits only the lockfile hash
so unchanged dependencies remain reusable after pin updates. GitHub caches are
immutable, so a changed lockfile saves a new archive. The override replaces the
base namespace, while GitHub's platform/lockfile suffixes still apply.

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
    cache-key: ios-dependencies-xcode-27-v1
```

With an explicit key, you own toolchain/package compatibility and key rotation.
Paths and keys are passed as literal arguments, not evaluated as shell code.

## Automatic cache selection

- When `tuist-cache-volume` is on `PATH` or available at `/__e/tuist-cache-volume`,
  attach a volume and use symlink materialization.
- Otherwise, use `actions/cache@v4` to restore/save `.build`, and copy package
  sources so archives do not retain SwifterPM's checkout-specific source links.

Selection happens before restoration. A volume client error is not silently
converted into archive caching; unavailable volume storage keeps the existing
empty-directory fallback. Each run uses only one backend. The `cache-backend`
output records the selection.

GitHub restores an exact key or a compatible prefix match and saves a new archive
after a successful job when the exact key was missing. Its normal branch/PR
scoping applies: fork PRs can read base-branch caches, while saves from a
`pull_request` run are scoped to that PR's merge ref. See
[GitHub's cache rules](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
Archive transfers and copies add overhead; caching is not a promise of faster
installation for every dependency graph.

## What is retained

Both backends retain workspace state, cached manifest JSON, downloaded sources,
and native compiled manifests. The action explicitly sets:

```text
--force-resolved-versions
--scratch-path <package>/.build
--cache-path <package>/.build/dependency-cache
```

Materialization is `symlink` for volumes and `copy` for GitHub archives.

The scratch path overrides configured `--scratch-path` options, keeping workspace
state in the retained directory. A nonempty `SWIFTPM_BUILD_DIR` is rejected because
it would redirect workspace state elsewhere. Leave the package-manifest
environment at `.automatic`; this action does not set an exclusion list.

Run the action before anything populates `.build`; do not combine it with another
cache step for that directory. Existing nonempty volume targets fail through the
volume action's normal contract; nothing is deleted or relocated. Unavailable
volume storage uses its empty job-local directory fallback, then installation
proceeds normally. Clearing `.build` also clears its dependency caches.

On Tuist Runners, fork PRs can use private writable clones of saved snapshots. The server controls
publication and never publishes fork changes. Retain only contents contributors
may read; keep secrets, authentication, and private source material outside the
cache. No workflow credential or `id-token` permission is required for volume attachment.

## Outputs

| Output | Meaning |
| --- | --- |
| `cache-hit` | `true` for a saved volume snapshot or exact GitHub archive hit. A GitHub prefix match reports `false`, even though data was restored. Installation always runs. |
| `cache-backend` | Automatically selected backend: `volume` or `github`. |
| `cache-path` | Absolute path to `.build/dependency-cache`. |

Use the cache output for later native SwiftPM commands:

```yaml
- uses: tuist/install@v1
  id: dependencies
- name: Resolve native package
  env:
    DEPENDENCY_CACHE: ${{ steps.dependencies.outputs.cache-path }}
  run: swift package --cache-path "$DEPENDENCY_CACHE" resolve --replace-scm-with-registry
```

Run native commands from their package directory. This action is for generated
projects using `tuist install`; it does not wrap standalone `swifterpm` or install
dependencies for vanilla Xcode projects.

## Development and release

Run `node --test .github/actions/install/action.test.mjs` and ShellCheck on the
shell entry points. The Install Action workflow tests the scripts and composite
wiring, and packages a standalone artifact containing the action, scripts, README,
license, and `SOURCE_COMMIT`.

One-time setup: create the `tuist/install` distribution repository with an initial
`main` commit and grant `TUIST_RELEASE_GITHUB_TOKEN` access. Then dispatch
`install-action.yml` on `main` with a stable version such as `v1.0.0` to publish
the tested checkout. Releases reuse the existing distribution publisher's atomic
push, immutable version tags, and moving major tag. An identical-source retry is
safe; a different source under an existing version is rejected. To retry after
main advances, dispatch the original main run again. Tests and packaging also run
on relevant pull requests and pushes; they never publish from pull requests.
