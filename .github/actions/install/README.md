# Tuist install

Install generated-project dependencies on Tuist Runners with one retained
workspace volume. The action attaches the package's `.build` directory and runs
`tuist install` with forced resolved versions, a nested dependency cache, and
symlink materialization. Installation runs even on a cache hit.

## Usage

The intended standalone entry point is `tuist/install@v1`. Until the first
release is published, use this action from a checkout of its monorepo source at
`.github/actions/install`, or pin `tuist/tuist/.github/actions/install@<commit>`.

After publication:

```yaml
jobs:
  generate:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist generate --no-open
```

Pin Tuist in your project's `mise.toml`. The action uses that installed CLI and
requires **4.214.0-canary.36 or newer**. Install tools and configure any private
package authentication before this step, without running `tuist install` from
setup hooks first. Commit `Package.resolved`. The selected Tuist runner must
support custom cache volumes; ordinary GitHub-hosted runners are not supported.

| Input | Default | Behavior |
| --- | --- | --- |
| `path` | `.` | Project directory inside `GITHUB_WORKSPACE`, relative to it or absolute. Subdirectories follow Tuist's root lookup. |
| `cache-key` | Generated | Override the complete volume key to share a compatible workspace between jobs, or rotate it. |

The action follows Tuist's root markers (`Tuist/`, `Tuist.swift`, `tuist.toml`,
`Plugin.swift`, or `.git/`) and prefers `Tuist/Package.swift` over a root
`Package.swift`. For a standalone project without a root marker, `path` must
contain `Package.swift`. It retains `.build` beside the selected package.

The default key hashes the job name, actual Swift/Xcode toolchain versions,
checkout-relative package location, and `Package.swift` contents, with a layout
version prefix. It excludes the lockfile, branch, run ID, and absolute checkout
path. Volume storage also scopes keys by repository, account, platform,
architecture, and execution user. Keep the default key unless jobs intentionally
share compatible workspace state.

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
    cache-key: ios-dependencies-xcode-27-v1
```

With an explicit key, you own toolchain/package compatibility and key rotation.
Paths and keys are passed as literal arguments, not evaluated as shell code.

## What is retained

The single volume contains workspace state, cached manifest JSON, downloaded
sources, and native compiled manifests. The action explicitly sets:

```text
--force-resolved-versions
--scratch-path <package>/.build
--cache-path <package>/.build/dependency-cache
--cached-directory-materialization=symlink
```

The scratch path overrides configured `--scratch-path` options, keeping workspace
state in the attached volume. A nonempty `SWIFTPM_BUILD_DIR` is rejected because
it would redirect workspace state elsewhere. Leave the package-manifest
environment at `.automatic`; this action does not set an exclusion list.

Attach before anything populates `.build`. Do not restore an archive into the
same directory. Existing nonempty paths fail through the volume action's normal
contract; nothing is deleted or relocated. Unavailable storage uses its empty
job-local directory fallback, then installation proceeds normally. Clearing
`.build` also clears its dependency caches.

Fork PRs can use private writable clones of saved snapshots. The server controls
publication and never publishes fork changes. Retain only contents contributors
may read; keep secrets, authentication, and private source material outside the
volume. No workflow credential or `id-token` permission is required for attachment.

## Outputs

| Output | Meaning |
| --- | --- |
| `cache-hit` | `true` when a saved snapshot was attached; otherwise `false`. This does not mean installation was skipped. |
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
