# swifterpm ⚡

`swifterpm` is a faster Swift package restoration tool built for workflows where dependency resolution happens often, across many clean worktrees, and under heavy concurrency.

## Motivation 🤖

Concurrent package installation is becoming the default in a world of coding agents. A single developer may now have several agents resolving dependencies in parallel, often across different worktrees of the same project. In that world, slow resolution and duplicated package checkouts become very expensive.

Other package managers have already iterated on this problem. Tools like pnpm and aube show that a global cache plus cheap project-local links can make installs both faster and much more disk efficient. Tuist users reported SwiftPM resolution and checkout restoration as a bottleneck, so we felt compelled to solve it for them.

Tuist generated projects gave us a clean contract to replace: package resolution is decoupled from project integration, so `tuist install` can use a faster resolver/restorer before Tuist generates or updates the Xcode project. `tuist install` uses `swifterpm` by default; set `TUIST_USE_SWIFTERPM=0` to fall back to SwiftPM.

> [!NOTE]
> [`aube`](https://github.com/endevco/aube) is useful prior art for package-manager acceleration in concurrent worktrees. `swifterpm` applies the same broad caching motivation to SwiftPM and Tuist workflows.

> [!IMPORTANT]
> `swifterpm` cannot transparently speed up standard Xcode projects. Xcode integrates SwiftPM internally, and that integration does not expose a supported hook where we can replace the resolver or checkout restorer. For now, this improvement is aimed at Tuist workflows and other flows that can call `swifterpm` before project integration.

## How it works

- **Resolution delegated to SwiftPM**: `swifterpm` does not reimplement the resolver. It shells out to `swift package resolve`, lets SwiftPM solve the graph and apply any source-control-to-registry transformation, then reads back and normalizes `Package.resolved` so the lockfile is byte-for-byte aligned with what SwiftPM would have written. The speedups all live in restoration and caching, not in the dependency solving.
- **Swift + Bazel implementation**: The CLI is written in Swift, uses structured concurrency for parallel restoration and async HTTP downloads, and is built with Bazel through `rules_swift` plus the `rules_apple` macOS command-line application wrapper.
- **Lockfile fast path**: When `Package.resolved` is available, `swifterpm` can use `--force-resolved-versions` to skip dependency solving and restore exactly the pinned revisions.
- **GitHub archives first**: For GitHub dependencies, it downloads source tarballs for pinned revisions instead of cloning full repositories. A shallow Git fetch is kept as a fallback.
- **Swift registry archives**: Registry packages declared with `.package(id:)` are resolved through SwiftPM-compatible registry configuration, downloaded as checksum-verified ZIP archives, and restored under `.build/registry/downloads`.
- **XDG global source cache**: Archives and extracted source trees are stored once under `$XDG_CACHE_HOME/swifterpm`, or `~/.cache/swifterpm` when `XDG_CACHE_HOME` is unset, keyed by package identity, version, and revision.
- **Project-local checkout shells**: `.build/checkouts` entries stay as real directories whose contents link back to the global cache, so Xcode and Tuist-relative paths keep resolving inside the worktree.
- **Concurrent-safe writes**: Package restoration runs in parallel, while cache writes use file locks, temporary files, and atomic moves so multiple installs can share the same cache safely.
- **Tuist package-info cache**: `swifterpm` can also persist SwiftPM manifest JSON under `.build/swifterpm/package-info`, allowing Tuist to avoid re-running parts of manifest loading later.

## Install and run

Install the latest release with mise:

```sh
mise use -g github:tuist/swifterpm@latest
```

Resolve and restore a package:

```sh
swifterpm --package-path . resolve
```

Use the fastest path when `Package.resolved` already exists:

```sh
swifterpm --package-path . --force-resolved-versions resolve
```

Or run without changing your mise config:

```sh
mise x github:tuist/swifterpm@latest -- swifterpm --package-path . --force-resolved-versions resolve
```

Useful SwiftPM-shaped flags are supported, including `--package-path`, `--cache-path`, `--scratch-path`, `--build-path`, `--config-path`, `--default-registry-url`, `--skip-update`, `--force-resolved-versions`, `--disable-automatic-resolution`, and `--only-use-versions-from-resolved-file`.

Authentication follows SwiftPM's separate registry, HTTP-download, and Git paths:

- **Registries** select one provider: `SWIFTPM_REGISTRY_TOKEN` or `SWIFTPM_REGISTRY_LOGIN`/`SWIFTPM_REGISTRY_PASSWORD`, then inline `SWIFTPM_NETRC_DATA`, then the macOS keychain (unless `--netrc` is passed), otherwise a netrc file. A missing credential in the selected provider does not fall through to another provider. Environment credentials are scoped to configured registry origins and respect the registry's configured Basic or token authentication type. On macOS, credentials stored only in a netrc file require `--netrc`, including when `--netrc-file` is supplied.
- **Binary artifacts and other HTTP downloads** try `SWIFTPM_SOURCE_CONTROL_TOKEN`, inline `SWIFTPM_NETRC_DATA`, a netrc file, then the keychain. The environment token uses Basic authentication with login `token` and, like SwiftPM, is sent to **every download host**, not just GitHub. Prefer host-scoped netrc credentials when a token must not be sent to unrelated hosts. `--disable-keychain` skips the keychain for these downloads, but does not change registry provider selection.
- **Git fetches and submodules** use Git's existing credential helpers, netrc, and URL rewrites. SwifterPM does not inject token headers or switch a declared HTTPS URL to SSH (or vice versa). Like SwiftPM, it supplies `GIT_TERMINAL_PROMPT=0` and `GIT_SSH_COMMAND="ssh -oBatchMode=yes"` only when those variables are absent. Git gives `GIT_SSH_COMMAND` precedence over `GIT_SSH` and `core.sshCommand`; set `GIT_SSH_COMMAND` explicitly if your SSH setup requires a custom command or deploy key.

The netrc file is `~/.netrc`, or the file given by `--netrc-file`. A missing or invalid explicit file is an error. Duplicate hosts use the last entry in files and the first entry in inline data, matching SwiftPM's respective providers. `--disable-netrc` disables file credentials for HTTP downloads only; inline data and registry netrc remain available, as they do in SwiftPM.

SwiftPM mirrors configured with `swift package config set-mirror` apply to source-control, registry, and remote binary target dependencies, so every download can go through an internal proxy. Mirrors load the way SwiftPM loads them: `SWIFTPM_MIRROR_CONFIG` or the package's `.swiftpm/configuration/mirrors.json` when it has entries, otherwise `mirrors.json` in `--config-path` or `~/.swiftpm/configuration`. Only exact locations are mapped, and a mirror may point at a git URL, a local path, or a registry identity (`scope.name`). As in SwiftPM, `Package.resolved` keeps the original location while checkouts and `workspace-state.json` use the mirror, a failing mirror is not retried against the original, and a pin whose identity no longer matches its mirror is resolved again. Git fetches from a mirror authenticate the way `git` does on its own (`~/.netrc` or a credential helper); binary artifact downloads use the netrc credentials above for the mirror's host, and registry downloads authenticate against the registry that serves the mirrored identity. The checksum declared for a binary target still applies.

Provider API optimizations (tag listing and source archive downloads) require an explicit `SWIFTERPM_GITHUB_TOKEN` or `SWIFTERPM_GITLAB_TOKEN`. These tokens are used only for the corresponding provider API, never Git fetches, submodules, or binary artifacts. GitLab API authentication requires HTTPS and a host matching `gitlab.com` or an explicit `SWIFTERPM_GITLAB_HOST`, `GITLAB_HOST`, `GITLAB_URI`, `GITLAB_API_HOST`, `CI_SERVER_HOST`, or `CI_SERVER_FQDN` configuration. Failed API requests fall back to Git with its configured credentials. This explicit optimization can read a private archive even when native Git cannot, so configure Git access as well to keep warm and cold resolution consistent. Ambient `GITHUB_TOKEN`, `GH_TOKEN`, `GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN`, `OAUTH_TOKEN`, and `CI_JOB_TOKEN` are not automatically discovered, and `gh`/`glab` credential stores are not consulted.

If you previously relied on automatic provider-token discovery, configure Git authentication as you would for native SwiftPM. Use the explicit SwifterPM variables only to opt into API optimizations; use host-scoped netrc, the keychain, or `SWIFTPM_SOURCE_CONTROL_TOKEN` for private binary artifacts.

By default, `swifterpm` copies cached directories into the project scratch directory during [continuous integration](https://en.wikipedia.org/wiki/Continuous_integration) (CI) and symlinks them elsewhere. Pass `--cached-directory-materialization=symlink` to preserve global-cache symlinks during continuous integration. The accepted values are `automatic`, `copy`, and `symlink`.

> [!NOTE]
> `swifterpm resolve` writes `Package.resolved` with an `originHash` derived from `Package.swift`, while SwiftPM derives its hash from the dependency graph. Running `swift package resolve` after `swifterpm resolve` in the same checkout may treat the lockfile as stale and resolve again.

## Continuous integration

> [!IMPORTANT]
> Cache `~/.cache/swifterpm` (or `$XDG_CACHE_HOME/swifterpm`). Without it, every continuous-integration run is a cold run.

The order-of-magnitude numbers in [Benchmarks](#benchmarks-) all come from the warm global cache, not from resolution itself, which is still delegated to SwiftPM. Warm runs range from 8.96x to 201x faster than SwiftPM. When any pin for the current package is missing from SwifterPM's source cache, SwifterPM delegates the installation directly to SwiftPM rather than doing a second restoration pass first. That keeps a cold package on SwiftPM's path while preserving SwifterPM's cache benefit once every pin is available.

The scratch directory (`.build`) is cold on every continuous-integration run regardless, since it lives in the freshly checked out workspace. The global cache is the only part that can carry over, and it is a new path that no pre-existing configuration knows about, so this bites hardest when switching an existing pipeline over:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cache/swifterpm
    key: swifterpm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
    restore-keys: swifterpm-${{ runner.os }}-
```

The cache is content-addressed by package identity, version, and revision, so a stale restore is safe: entries that no longer match are simply unused, and `restore-keys` lets a run start from the closest previous cache instead of from nothing.

For a persistent runner that keeps the SwifterPM cache on disk between jobs, configure symlink materialization. It avoids copying every cached checkout into a new scratch directory, leaving the warm path as inexpensive links back to the persistent cache.

Package manifests can read process environment variables while declaring dependencies, so the package-manager cache keys include the environment they observe. Tuist automatically hides volatile run metadata when it recognizes [GitLab](https://docs.gitlab.com/ci/variables/predefined_variables/), [GitHub Actions](https://docs.github.com/actions/reference/workflows-and-actions/variables), [Bitrise](https://docs.bitrise.io/en/bitrise-ci/references/available-environment-variables/), or [Codemagic](https://docs.codemagic.io/yaml-basic-configuration/environment-variables/). This keeps job or run identifiers, retry counts, and per-step temporary paths from needlessly making a warm manifest cache cold. Branch, reference, commit, workflow, and other configuration values remain visible.

Restore an automatically excluded variable only when a package manifest intentionally uses it to declare dependencies:

```swift
let config = Config(
    project: .tuist(
        installOptions: .options(
            packageManifestEnvironment: .automatic(including: ["CI_JOB_ID"])
        )
    )
)
```

Use `packageManifestEnvironment: .all` to preserve the complete process environment, or add organization-specific volatile values with `packageManifestEnvironment: .automatic(excluding: ["BUILD_RUN_*"])`. Tuist supplies the resulting environment to the package resolver as well as `Package.swift`, so never exclude credentials or another value needed to fetch a dependency. Entries can be literal names or trailing-wildcard prefixes such as `GITHUB_RUN_*`; included entries take precedence over automatic and custom exclusions.

## Bazel Swift package resolver

`swifterpm` also ships a Bzlmod extension with the same resolver helper shape as `rules_swift_package_manager`:

```starlark
bazel_dep(name = "swifterpm", version = "0.9.0")

swift_deps = use_extension("@swifterpm//:extensions.bzl", "swift_deps")
swift_deps.from_package(
    resolved = "//:Package.resolved",
    swift = "//:Package.swift",
)
use_repo(swift_deps, "swift_package")
```

Then run:

```sh
bazel run @swift_package//:resolve
bazel run @swift_package//:update
```

The generated `@swift_package` repository downloads the matching `swifterpm-${version}-${target}.tar.gz` binary from GitHub releases and uses it to update `Package.resolved`. For local rule development, override the tool with:

```starlark
swift_deps.configure_swifterpm(
    local_binary = "/absolute/path/to/swifterpm",
)
```

This currently covers the resolver helper API. It does not yet synthesize `swiftpkg_<identity>` Bazel build repositories for package targets.

## Buck2 Apple build setup

For Buck2-based Apple builds, `swifterpm` ships a small macro that creates an executable restore target. Copy or vendor [swifterpm/buck2/swifterpm.bzl](swifterpm/buck2/swifterpm.bzl), then load it from your `BUCK` file:

```python
load("//build_defs:swifterpm.bzl", "swifterpm_restore")

swifterpm_restore(
    name = "restore_swift_packages",
    package = "Package.swift",
)
```

Run it before Apple build targets that read sources from `.build/checkouts`:

```sh
buck2 run //:restore_swift_packages
buck2 build //App:App
```

The generated target runs `swifterpm resolve --print-only --write` followed by `swifterpm restore`. It uses `swifterpm` from `PATH` by default, or `SWIFTERPM_BIN` when set. If the package root differs from the Buck2 invocation directory, set `SWIFTERPM_PACKAGE_ROOT` to the directory containing `Package.swift`.

This currently provides the restore hook for Apple build setup. It does not synthesize Buck2 targets for Swift package products.

## Build from source

Build the command-line binary:

```sh
mise exec -- bazel build //:swifterpm
```

Build the Apple rules wrapper:

```sh
mise exec -- bazel build //:swifterpm_macos
```

## Benchmarks 📊

The benchmark script is [mise/tasks/benchmark/resolution.sh](mise/tasks/benchmark/resolution.sh). It clones or copies each codebase into a temporary directory, deletes it on completion, and compares SwiftPM against `swifterpm` for cold resolution and worktree-warm resolution.

Run it with:

```sh
mise run benchmark:resolution -- --runs 3
```

Add `--tuist-source ../tuist` to use a local Tuist checkout instead of cloning `tuist/tuist`.

The script writes Markdown and JSON reports under `benchmark-results`.

Representative one-run sample from the latest cache-isolated setup, generated on Apple Swift 6.3.2:

| Codebase | Scenario | SwiftPM | swifterpm | Time reduction | Speedup |
|:---|:---|---:|---:|---:|---:|
| Pocket Casts iOS `Modules/Package.swift` | Cold | 438.106 s | 258.544 s | 40.99% | 1.69x |
| Pocket Casts iOS `Modules/Package.swift` | Worktree-warm | 101.048 s | 0.502 s | 99.50% | 201.15x |
| Firefox iOS root `Package.swift` | Cold | 107.358 s | 11.738 s | 89.07% | 9.15x |
| Firefox iOS root `Package.swift` | Worktree-warm | 4.471 s | 0.421 s | 90.59% | 10.63x |
| Tuist root `Package.swift` | Cold | 131.391 s | 109.059 s | 17.00% | 1.20x |
| Tuist root `Package.swift` | Worktree-warm | 33.290 s | 1.484 s | 95.54% | 22.44x |
| SwiftNIO fixture `third_party/nio/Package.swift` | Cold | 5.535 s | 7.120 s | -28.63% | 0.78x |
| SwiftNIO fixture `third_party/nio/Package.swift` | Worktree-warm | 1.945 s | 0.217 s | 88.84% | 8.96x |

Cold resolution removes package-local scratch directories plus each tool's benchmark-local shared cache before each measured run. Worktree-warm resolution removes package-local scratch directories before each measured run while keeping each tool's already-primed benchmark-local shared cache, which models switching to another clean worktree.

Both tools are run against the same `Package.resolved` file with forced resolved versions. The benchmark passes `--cache-path` to SwiftPM so local user-level SwiftPM caches do not make the SwiftPM cold run warmer than the `swifterpm` cold run. Tuist's temporary benchmark clone refreshes `Package.resolved` before timing because the current `tuist/tuist` main branch has an out-of-date checked-in lockfile. SwiftNIO uses this repository's pinned `third_party/nio` fixture because upstream SwiftNIO does not commit a root `Package.resolved`.
