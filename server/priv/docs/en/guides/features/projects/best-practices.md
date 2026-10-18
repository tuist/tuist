---
{
  "title": "Best practices",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the best practices for working with Tuist-generated projects."
}
---
# Best practices {#best-practices}

Over the years working with different teams and projects, we've identified a set of best practices that we recommend following when working with Tuist and Xcode projects. These practices are not mandatory, but they can help you structure your projects in a way that makes them easier to maintain and scale.

## Xcode {#xcode}

### Discouraged patterns {#discouraged-patterns}

#### Configurations to model remote environments {#configurations-to-model-remote-environments}

Many organizations use build configurations to model different remote environments (e.g., `Debug-Production` or `Release-Canary`), but this approach has some downsides:

- **Inconsistencies:** If there are configuration inconsistencies throughout the graph, the build system might end up using the wrong configuration for some targets.
- **Complexity:** Projects can end up with a long list of local configurations and remote environments that are hard to reason about and maintain.

Build configurations were designed to embody different build settings, and projects rarely need more than just `Debug` and `Release`. The need to model different environments can be achieved differently:

- **In Debug builds:** You can include all the configurations that should be accessible in development in the app (e.g. endpoints), and switch them at runtime. The switch can happen either using scheme launch environment variables, or with a UI within the app.
- **In Release builds:** In case of release, you can only include the configuration that the release build is bound to, and not include the runtime logic for switching configurations by using compiler directives.

> [!NOTE]
> **Non-standard Configurations**
>
> While Tuist supports non-standard configurations and makes them easier to manage compared to vanilla Xcode projects, you'll receive warnings if configurations are not consistent throughout the dependency graph. This helps ensure build reliability and prevents configuration-related issues.


## Generated projects

### Buildable folders

Tuist 4.62.0 added support for **buildable folders** (Xcode's synchronized groups), a feature introduced in Xcode 16 to reduce merge conflicts.

While Tuist's wildcard patterns (e.g., `Sources/**/*.swift`) already eliminate merge conflicts in generated projects, buildable folders offer additional benefits:

- **Automatic synchronization**: Your project structure stays in sync with the file system—no regeneration needed when adding or removing files
- **AI-friendly workflows**: Coding assistants and agents can modify your codebase without triggering project regeneration
- **Simpler configuration**: Define folder paths instead of managing explicit file lists

We recommend adopting buildable folders instead of traditional `Target.sources` and `Target.resources` attributes for a more streamlined development experience.

::: code-group

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### Dependencies

#### Force resolved versions on CI

When installing Swift Package Manager dependencies on CI, we recommend using the `--force-resolved-versions` flag to ensure deterministic builds:

```bash
tuist install --force-resolved-versions
```

This flag ensures that dependencies are resolved using the exact versions pinned in `Package.resolved`, eliminating issues caused by non-determinism in dependency resolution. This is particularly important on CI where reproducible builds are critical.

#### Dependency installation on continuous-integration runners

For generated projects using Tuist's package integration, `tuist install` uses [SwifterPM](https://github.com/tuist/swifterpm). SwifterPM maintains a local source cache and restores package checkouts from it when possible. On an ephemeral continuous-integration runner without retained cache storage, every job starts without that cache, so installation follows the native [Swift Package Manager](https://www.swift.org/package-manager/) path. No additional configuration is needed.

Package manifests can read process environment variables while declaring dependencies. The package-manifest cache therefore accounts for those variables. Job-specific values can change on every run without changing the declared dependencies, which would otherwise prevent a cache hit.

`packageManifestEnvironment` defaults to `.automatic`; no `Tuist.swift` override or explicit exclusion list is needed for a typical CI workflow. On GitHub Actions, it excludes `GITHUB_*`, `ACTIONS_*`, `RUNNER_*`, and `SSH_AUTH_SOCK` from cached manifest evaluation, while preserving `GITHUB_ACTIONS`, `RUNNER_OS`, and `RUNNER_ARCH`. This also excludes branch, reference, commit, and workflow metadata. Toolchain settings and application-defined inputs remain visible and participate in cache keys.

Tuist also filters selected volatile execution identifiers on GitLab, Bitrise, and Codemagic, and excludes Tuist cache-signing grants and runner pod identities on every provider. These defaults apply on both ephemeral and persistent runners. The expanded GitHub defaults and manifest-cache reuse across fresh checkout timestamps are available in `4.214.0-canary.33`; use that release or a later release containing these changes.

If a package manifest intentionally uses one of the automatic exclusions to declare dependencies, restore that variable explicitly in `Tuist.swift`:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(
            packageManifestEnvironment: .automatic(
                including: ["CI_JOB_ID"]
            )
        )
    )
)
```

Use `packageManifestEnvironment: .all` to preserve the complete process environment. You can also exclude organization-specific volatile values with `packageManifestEnvironment: .automatic(excluding: ["BUILD_RUN_*"])`. The automatic policy keeps known GitHub/SSH authentication inputs available to native dependency resolution, while excluding them from cached manifest evaluation. Native resolution can also evaluate manifests; if a manifest intentionally reads those inputs, include them explicitly so both paths see the same values. Custom exclusions also apply to native resolution, so do not explicitly exclude credentials needed to fetch dependencies. Entries can be exact names or trailing-wildcard prefixes such as `GITHUB_RUN_*`; included entries take precedence over automatic and custom exclusions.

#### Cached dependency installation on GitHub Actions {#dependency-cache-volumes}

For generated projects, use [tuist/install](https://github.com/tuist/install) to install pinned dependencies and retain their caches with one step. On Tuist Runners, the action attaches a <.localized_link href="/guides/features/runners/cache-volumes">cache volume</.localized_link> and reuses package sources through symlinks. On other runners, it automatically uses GitHub's archive cache and copies sources so the archive remains usable across checkouts. No cache-provider input is needed.

Commit `Package.resolved` beside your package manifest. The action uses the already-installed CLI; install your tools and configure private-package authentication before it runs. Keep `packageManifestEnvironment` at its `.automatic` default.

```yaml
name: Generate project
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  generate:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist generate --no-open
```

Use `macos-latest` for a GitHub-hosted runner; the install step stays the same. Cache volumes do not require a larger Tuist runner profile.

The action discovers `Tuist/Package.swift` or a root `Package.swift` and retains `.build` beside it. Workspace state, downloaded sources, cached manifest JSON, and native compiled manifests share that directory, with the dependency cache under `.build/dependency-cache`. It sets the scratch/cache paths and materialization mode, and always runs `tuist install --force-resolved-versions`, including on cache hits, to validate the current lockfile. There is no need to repeat those flags or attach a separate volume. Cleaning `.build` also clears its dependency caches.

For a project in a subdirectory, pass its path relative to the checkout:

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

By default, the cache namespace separates jobs, Swift/Xcode toolchains, package locations, and manifest contents. Volume keys exclude the lockfile so unchanged sources remain reusable after pin updates. GitHub archive keys additionally include the platform, architecture, and lockfile hash, and can restore a compatible older archive when pins change. Only override `cache-key` when intentionally sharing compatible state or rotating the cache; see the [action reference](https://github.com/tuist/install#usage) for inputs and outputs.

Run the action before any command or tool-installation hook populates `.build`, and remove other archive-cache or volume steps for that directory. The action controls its scratch path; leave `SWIFTPM_BUILD_DIR` unset. Ignore the workspace symlink without a trailing slash in `.gitignore`, for example `Tuist/.build`.

The first eligible successful default-branch run seeds a volume; later jobs reuse it under the <.localized_link href="/guides/features/runners/cache-volumes#saving-changes">normal saving policy</.localized_link>. If volume storage is unavailable, attachment supplies an empty job-local directory and installation repopulates it. A volume error does not switch the job to archive caching. On runners using GitHub caches, an exact miss saves a new archive after a successful job. Cache transfer and source-copy overhead vary by dependency graph, so retained caches do not guarantee faster installation for every project.

### Agentic coding and worktrees {#agentic-coding-and-worktrees}

Coding agents and human contributors increasingly work in parallel: a developer keeps a worktree open for the feature they are reviewing while one or more agents iterate on their own branches in sibling worktrees. A few project choices make this much smoother.

#### Use buildable folders for agent-driven edits {#worktrees-buildable-folders}

When an agent adds or removes files, anything that depends on a file list in `Project.swift` requires `tuist generate` before the project builds again. [Buildable folders](#buildable-folders) push that responsibility down to Xcode's synchronized groups, so file-tree edits no longer trigger a regeneration.

Pair this with the `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">skill</.localized_link>, which teaches agents the day-to-day workflow of a Tuist project.

#### Don't isolate the cache per worktree {#worktrees-shared-cache}

Tuist follows the <.localized_link href="/cli/directories">XDG Base Directory Specification</.localized_link>, so by default every worktree on the same machine shares `~/.cache/tuist` and `~/.local/state/tuist`. That is what you want: helpers compiled in one worktree, plugins downloaded in another, and module-cache binaries pulled by a third are all reusable.

Concurrent `tuist` invocations across worktrees are safe to run in parallel. Avoid pointing `TUIST_XDG_CACHE_HOME` at a worktree-local path unless you specifically need isolation; doing so forces every worktree to re-warm helpers, plugins, and binaries.

#### Keep SwiftPM scratch per worktree {#worktrees-swiftpm-scratch}

Swift Package Manager has its own path controls. `--scratch-path` is mutable working state and defaults to `.build`, while `--cache-path` is the shared cache directory. Those two paths should not be treated the same when several worktrees are active.

Tuist's default `tuist install` behavior already keeps SwiftPM scratch under the package directory, so each worktree gets its own `.build`. Keep that isolation. A single shared SwiftPM scratch directory can mix checkouts, build intermediates, plugins, macros, and lock files from unrelated branches.

If you pass SwiftPM arguments through `tuist install -- ...` or through `installOptions` in `Tuist.swift`, share `--cache-path` when you want faster dependency fetches, but leave `--scratch-path` unset or point it at a worktree-local directory:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: [
                "--cache-path",
                "/Users/Shared/swiftpm/cache/xcode-16-macos",
            ]
        )
    )
)
```

Use a wrapper or CI environment variable for the cache path if it needs to vary by Xcode, Swift toolchain, or platform. Avoid committing a shared `--scratch-path` to the repository.

If dependency state looks corrupted in only one worktree, delete that worktree's `.build` directory and run `tuist install` again. If the shared SwiftPM cache itself looks suspect across worktrees, use `swift package purge-cache` before re-installing dependencies.

#### Lean on the module cache {#worktrees-module-cache}

The <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> is what makes parallel worktrees tractable. Because Tuist computes a deterministic <.localized_link href="/guides/features/projects/hashing">hash</.localized_link> for each target, two worktrees pointing at branches that share most of their history will hit the same binaries. Run `tuist cache` on every commit to `main` from CI; locally, `tuist generate` in each worktree pulls whatever it can from the cache and only builds what your branch actually changed.

If a worktree falls back to source builds when you expected a cache hit, follow the <.localized_link href="/guides/features/projects/hashing#debugging">hashing debugging steps</.localized_link>; non-deterministic hashes (typically caused by absolute paths in the project) are the most common cause and they show up loudly when comparing two worktrees.

#### Speed up Swift Package resolution with the registry {#worktrees-registry}

Each worktree resolves Swift packages independently. On a project with a large dependency graph that adds up fast. Switching to the <.localized_link href="/guides/features/package-registries/swift">Tuist Registry</.localized_link> avoids re-cloning git histories and drops resolution from minutes to seconds.

#### Give agents access to project insights {#worktrees-mcp}

Once builds and tests are running across many worktrees, the most useful thing an agent can do is reason about *which* of those runs regressed, which tests are flaky, or how the bundle size has changed. Tuist exposes that data through the <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> and the <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> package. Pick one per workflow and stick to it; mixing both for the same task tends to produce inconsistent agent behavior.
