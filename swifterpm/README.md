# swifterpm ⚡

`swifterpm` is a faster Swift package restoration tool built for workflows where dependency resolution happens often, across many clean worktrees, and under heavy concurrency.

## Motivation 🤖

Concurrent package installation is becoming the default in a world of coding agents. A single developer may now have several agents resolving dependencies in parallel, often across different worktrees of the same project. In that world, slow resolution and duplicated package checkouts become very expensive.

Other package managers have already iterated on this problem. Tools like pnpm and aube show that a global cache plus cheap project-local links can make installs both faster and much more disk efficient. Tuist users reported SwiftPM resolution and checkout restoration as a bottleneck, so we felt compelled to solve it for them.

Tuist generated projects gave us a clean contract to replace: package resolution is decoupled from project integration, so `tuist install` can use a faster resolver/restorer before Tuist generates or updates the Xcode project.

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

By default, `swifterpm` copies cached directories into the project scratch directory on CI and symlinks them elsewhere. Pass `--cached-directory-materialization symlink` to preserve global-cache symlinks on CI. The accepted values are `automatic`, `copy`, and `symlink`.

> [!NOTE]
> `swifterpm resolve` writes `Package.resolved` with an `originHash` derived from `Package.swift`, while SwiftPM derives its hash from the dependency graph. Running `swift package resolve` after `swifterpm resolve` in the same checkout may treat the lockfile as stale and resolve again.

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
