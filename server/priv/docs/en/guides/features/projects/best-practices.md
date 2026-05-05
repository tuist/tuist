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

### Agentic coding and worktrees {#agentic-coding-and-worktrees}

Coding agents and human contributors increasingly work in parallel: a developer keeps a worktree open for the feature they are reviewing while one or more agents iterate on their own branches in sibling worktrees. A few project choices make this much smoother.

#### Use buildable folders for agent-driven edits {#worktrees-buildable-folders}

When an agent adds or removes files, anything that depends on a file list in `Project.swift` requires `tuist generate` before the project builds again. [Buildable folders](#buildable-folders) push that responsibility down to Xcode's synchronized groups, so file-tree edits no longer trigger a regeneration.

Pair this with the `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">skill</.localized_link>, which teaches agents the day-to-day workflow of a Tuist project.

#### Don't isolate the cache per worktree {#worktrees-shared-cache}

Tuist follows the <.localized_link href="/cli/directories">XDG Base Directory Specification</.localized_link>, so by default every worktree on the same machine shares `~/.cache/tuist` and `~/.local/state/tuist`. That is what you want: helpers compiled in one worktree, plugins downloaded in another, and module-cache binaries pulled by a third are all reusable.

Concurrent `tuist` invocations across worktrees are safe to run in parallel. Avoid pointing `TUIST_XDG_CACHE_HOME` at a worktree-local path unless you specifically need isolation; doing so forces every worktree to re-warm helpers, plugins, and binaries.

#### Lean on the module cache {#worktrees-module-cache}

The <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> is what makes parallel worktrees tractable. Because Tuist computes a deterministic <.localized_link href="/guides/features/projects/hashing">hash</.localized_link> for each target, two worktrees pointing at branches that share most of their history will hit the same binaries. Run `tuist cache` on every commit to `main` from CI; locally, `tuist generate` in each worktree pulls whatever it can from the cache and only builds what your branch actually changed.

If a worktree falls back to source builds when you expected a cache hit, follow the <.localized_link href="/guides/features/projects/hashing#debugging">hashing debugging steps</.localized_link>; non-deterministic hashes (typically caused by absolute paths in the project) are the most common cause and they show up loudly when comparing two worktrees.

#### Speed up Swift Package resolution with the registry {#worktrees-registry}

Each worktree resolves Swift packages independently. On a project with a large dependency graph that adds up fast. Switching to the <.localized_link href="/guides/features/registry">Tuist Registry</.localized_link> avoids re-cloning git histories and drops resolution from minutes to seconds.

#### Give agents access to project insights {#worktrees-mcp}

Once builds and tests are running across many worktrees, the most useful thing an agent can do is reason about *which* of those runs regressed, which tests are flaky, or how the bundle size has changed. Tuist exposes that data through the <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> and the <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> package. Pick one per workflow and stick to it; mixing both for the same task tends to produce inconsistent agent behavior.
