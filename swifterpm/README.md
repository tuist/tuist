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

### Private registries on older toolchains

A cold cache, an update, or a changed dependency graph may invoke native SwiftPM. Upstream SwiftPM added environment credential providers in Swift 6.3.2, not the initial Swift 6.3 release. SwifterPM checks the selected `swift --version` before delegating; unknown versions use the conservative compatibility path.

For older toolchains, SwifterPM can bridge **inline `SWIFTPM_NETRC_DATA`** to a temporary netrc file. Inline credentials are already host-scoped, and first-match duplicate semantics are preserved. The file uses unquoted tokens so Swift 6.0 can parse it too. Empty tokens and tokens containing whitespace, `#`, quotes, or NUL are rejected with a redacted error instead of silently changing the credential or producing a downstream 401. The bridge requires an explicit authentication type in the registry configuration, and either no file netrc credentials or `--disable-netrc`. It refuses to merge file credentials because registry provider selection and HTTP credential fallback cannot both be preserved in one merged file.

For example, configure the registry in the package's `.swiftpm/configuration/registries.json`:

```json
{
  "version": 1,
  "registries": {
    "[default]": { "url": "https://registry.example.com" }
  },
  "authentication": {
    "registry.example.com": { "type": "token" }
  }
}
```

Then supply a CI secret through inline netrc:

```sh
export SWIFTPM_NETRC_DATA="machine registry.example.com login token password ${REGISTRY_TOKEN}"
tuist install --disable-netrc
```

Use `"basic"` instead of `"token"` for a Basic-authenticated registry. Authentication keys include the port when the registry URL declares one, for example `registry.example.com:8443`. Netrc credentials match the hostname, not the scheme or port, and also authenticate HTTP artifact downloads on that host; choose their scope deliberately.

SwifterPM does **not** translate `SWIFTPM_REGISTRY_TOKEN`, registry login/password variables, or `SWIFTPM_SOURCE_CONTROL_TOKEN` into netrc on older toolchains. That would broaden origin-scoped registry credentials or change global HTTP authentication. Use inline netrc explicitly, a credential file with `tuist install --netrc --netrc-file /secure/path/registry.netrc`, or a toolchain with native environment-provider support. When choosing file or keychain credentials on an older toolchain, unset the environment credential variables first. These registry compatibility checks apply only when declared dependencies, known registry pins reachable through source-control dependencies, or source-control transformation indicate registry use. An unused local or global registry setting does not block dependency-free or source-control-only packages. Transitive registry dependencies absent from both the manifest graph and existing pins remain native SwiftPM's responsibility. Warm lockfile validation does not fetch packages and bypasses compatibility refusals. Do not exclude credentials needed by native resolution from its environment; excluded secrets are not silently reinserted into manifest evaluation.

The bridge does not rewrite registry configuration, mirrors, or the user's netrc. A separate subprocess owns a mode-0700 directory and mode-0600 credential file, receives the contents only over stdin, and removes them on completion, failure, cancellation, or launcher exit. As with any disk-backed secret, killing the entire process group with SIGKILL or losing power may leave a private temporary file until the OS cleans it up.

### Keychain access in CI

Credentials stored by `swift package-registry login` may authorize Swift but not the Tuist executable. Unlocking a keychain alone does not grant another executable access to an item. In CI or without a terminal, SwifterPM reads the keychain **in-process**, so items already authorized for Tuist retain that trust. It disables legacy approval dialogs only around the synchronous lookup and restores the previous interaction setting on success or failure. SwifterPM serializes its keychain reads to prevent overlapping policy changes; the setting is process-wide, so other embedding code also observes it during that short headless lookup. Interactive reads leave the policy untouched. No interpreter, credential subprocess, or helper protocol is involved.

Concurrent lookups share a resolution-scoped cache keyed by protocol, host, and explicit port; credentials are not retained across installations. Cancellation detaches individual callers and cancels shared work when its last caller leaves, but cannot interrupt a Security framework call already in progress. An actual missing item remains a normal provider miss. Denied registry access produces actionable diagnostics instead of hanging or falling through to a different credential provider. If the interaction policy cannot be established, registry requests warn and can proceed anonymously; HTTP downloads can continue anonymously after either access denial or policy failure. Warnings use the embedding CLI's callback (`SwifterPM.withWarningHandler`) and respect quiet mode. Neither path swallows cancellation.

SwiftPM mirrors configured with `swift package config set-mirror` apply to source-control, registry, and remote binary target dependencies, so every download can go through an internal proxy. Mirrors load the way SwiftPM loads them: `SWIFTPM_MIRROR_CONFIG` or the package's `.swiftpm/configuration/mirrors.json` when it has entries, otherwise `mirrors.json` in `--config-path` or `~/.swiftpm/configuration`. Only exact locations are mapped, and a mirror may point at a git URL, a local path, or a registry identity (`scope.name`). As in SwiftPM, `Package.resolved` keeps the original location while checkouts and `workspace-state.json` use the mirror, a failing mirror is not retried against the original, and a pin whose identity no longer matches its mirror is resolved again. Git fetches from a mirror authenticate the way `git` does on its own (`~/.netrc` or a credential helper); binary artifact downloads use the netrc credentials above for the mirror's host, and registry downloads authenticate against the registry that serves the mirrored identity. The checksum declared for a binary target still applies.

Provider API optimizations (tag listing and source archive downloads) require an explicit `SWIFTERPM_GITHUB_TOKEN` or `SWIFTERPM_GITLAB_TOKEN`. These tokens are used only for the corresponding provider API, never Git fetches, submodules, or binary artifacts. GitLab API authentication requires HTTPS and a host matching `gitlab.com` or an explicit `SWIFTERPM_GITLAB_HOST`, `GITLAB_HOST`, `GITLAB_URI`, `GITLAB_API_HOST`, `CI_SERVER_HOST`, or `CI_SERVER_FQDN` configuration. Failed API requests fall back to Git with its configured credentials. This explicit optimization can read a private archive even when native Git cannot, so configure Git access as well to keep warm and cold resolution consistent. Ambient `GITHUB_TOKEN`, `GH_TOKEN`, `GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN`, `OAUTH_TOKEN`, and `CI_JOB_TOKEN` are not automatically discovered, and `gh`/`glab` credential stores are not consulted.

If you previously relied on automatic provider-token discovery, configure Git authentication as you would for native SwiftPM. Use the explicit SwifterPM variables only to opt into API optimizations; use host-scoped netrc, the keychain, or `SWIFTPM_SOURCE_CONTROL_TOKEN` for private binary artifacts.

`swifterpm restore`, used by the Buck2 and Bazel helpers, never delegates to native SwiftPM. These changes therefore change restore behavior, unlike cold `resolve` or `tuist install`, which already delegate to native SwiftPM. With a cold cache and no SSH access, an SSH-declared dependency now fails instead of restoring through automatic `GH_TOKEN` discovery or an anonymous HTTPS fallback, even when the repository is public. Configure Git access for the declared transport, or explicitly use a mirror or Git URL rewrite if HTTPS is required. `SWIFTERPM_GITHUB_TOKEN` can still enable source archives, but does not authenticate Git. For deploy keys previously configured through `core.sshCommand` or `GIT_SSH`, set `GIT_SSH_COMMAND` explicitly so the native-style default does not override the custom command.

By default, `swifterpm` copies cached directories into the project scratch directory during [continuous integration](https://en.wikipedia.org/wiki/Continuous_integration) (CI) and symlinks them elsewhere. Pass `--cached-directory-materialization=symlink` to preserve global-cache symlinks during continuous integration. The accepted values are `automatic`, `copy`, and `symlink`.

An explicit `--cache-path` also applies to native manifest compilation, including SwifterPM's internal `swift package dump-package` calls. For generated projects using `tuist install`, this allows dependency sources and native manifest caches to live beside workspace state in one retained `.build` directory:

```bash
tuist install --force-resolved-versions \
  --cache-path "$PWD/.build/dependency-cache" \
  --cached-directory-materialization=symlink
```

This example assumes `Package.swift` is at the repository root. For `Tuist/Package.swift`, use `$PWD/Tuist/.build/dependency-cache` and retain `Tuist/.build`. Always run installation on a cache hit to validate the lockfile. Cleaning `.build` also removes these caches; keeping them within a job's workspace trades sharing across jobs or worktrees for a single retained directory. Omitting `--cache-path` preserves the existing shared-cache locations. SwiftPM configuration and authentication remain outside this cache.

Alternatively, retain only an external cache such as `--cache-path "$HOME/.cache/swifterpm"` and recreate `.build` on each job. Sources and native compiled manifests remain reusable, but workspace state and SwifterPM's cached manifest JSON must be regenerated. Measure installation time for your dependency graph before choosing which layout to retain.

> [!NOTE]
> `swifterpm resolve` writes `Package.resolved` with an `originHash` derived from `Package.swift`, while SwiftPM derives its hash from the dependency graph. Running `swift package resolve` after `swifterpm resolve` in the same checkout may treat the lockfile as stale and resolve again.

## Source cache ownership and compatibility

Before invoking native SwiftPM, SwifterPM detaches Git-bearing checkout links so SwiftPM supplies its own working copies. Git-free checkout links and binary artifacts are privately materialized, using directory copy-on-write cloning on supported macOS filesystems and independent copies elsewhere. Native Git operations therefore cannot rewrite the shared cache through those links, and a failed native run cannot strand a private copy of an already-damaged shared Git tree. Tuist applies the same preparation when `TUIST_USE_SWIFTERPM=0` is used.

Native checkout publication exports the pinned Git commit through a temporary index and empty working tree, including initialized submodules. It does not import staged changes, untracked files, or arbitrary working-tree bytes. Git metadata is excluded from published snapshots. If export fails, the native checkout is retained rather than stamped as a trustworthy cache entry.

Existing cache paths, revision markers, registry downloads, and CI materialization options remain unchanged. Ordinary Git-free cache hits still share sources through links outside CI, without a new source-tree hashing pass or Git subprocess per package. Native preparation and force-resolved verification may leave private copies; a subsequent ordinary install can relink them.

Native resolution, update, and `--force-resolved-versions` validation privately materialize every linked source checkout and binary artifact they encounter. APFS clones share file data, but their metadata work still scales with the number of files; independent-copy fallback also copies the data. This can add noticeable time on large graphs, both for the native invocation and for the next ordinary install that discards those private trees and restores cache links. A matching revision marker is not proof that native execution will leave a shared tree untouched, or that its private copy still matches the pinned source afterward. The marker therefore does not bypass the ownership boundary, and private native copies are not reused as certified cache contents.

Legacy shared entries that still contain `.git` are left untouched. Their pinned Git objects are restored to a private checkout in each worktree, which is reused on warm installs. Local source-control entries keep private Git metadata and tags to preserve their existing `Context.gitInformation`. A shallow transport clone copies the pinned objects rather than hard-linking them or retaining alternates to a replaceable/cache directory; working files, objects, index and HEAD are independent. Other legacy entries become Git-free snapshots, which can change manifests relying on `Context.gitInformation`. The local compatibility path preserves pinned commit/tag context, not the repository's full history or unrelated tags. This first restore writes a full source tree per worktree. If the legacy objects are unavailable, each worktree fetches the pin privately.

Modified or unreadable real Git checkouts and unmanaged Git-free directories are preserved with a diagnostic, not silently imported or deleted. Clean older Git checkouts can be replaced only when their HEAD is still reachable from remote or tag refs and no unpublished branch commits exist; otherwise move them aside explicitly, even if the working files are clean. A preserved directory may also be a private copy of a damaged legacy entry left by an earlier version or interrupted invocation. Move it aside, rather than discarding it, before rebuilding from pinned sources. SwiftPM edited dependencies are rejected without clearing their edit state; use native SwiftPM or unedit them first.

These protections do not certify already-corrupted Git-free cache entries whose revision marker still matches, prevent older binaries from modifying their cache, or isolate arbitrary editor/build/plugin writes through warm source links. Such entries need explicit, scoped recovery; installing this version is not a universal cache repair.

## Continuous integration

Manifest dumps and package-info JSON use content fingerprints and stay under the root
scratch directory, so identical fresh checkouts can reuse retained caches. Older entries
refresh once on upgrade. Manifests that read arbitrary external files still require
explicit cache invalidation; SwifterPM does not trace those reads.

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
