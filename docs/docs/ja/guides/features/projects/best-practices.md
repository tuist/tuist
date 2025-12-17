---
{
  "title": "Best practices",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the best practices for working with Tuist and Xcode projects."
}
---
# Best practices {#best-practices}

Over the years working with different teams and projects, we've identified a set
of best practices that we recommend following when working with Tuist and Xcode
projects. These practices are not mandatory, but they can help you structure
your projects in a way that makes them easier to maintain and scale.

## Xcode {#xcode}

### Discouraged patterns {#discouraged-patterns}

#### Configurations to model remote environments {#configurations-to-model-remote-environments}

Many organizations use build configurations to model different remote
environments (e.g., `Debug-Production` or `Release-Canary`), but this approach
has some downsides:

- **Inconsistencies:** If there are configuration inconsistencies throughout the
  graph, the build system might end up using the wrong configuration for some
  targets.
- **Complexity:** Projects can end up with a long list of local configurations
  and remote environments that are hard to reason about and maintain.

Build configurations were designed to embody different build settings, and
projects rarely need more than just `Debug` and `Release`. The need to model
different environments can be achieved differently:

- **In Debug builds:** You can include all the configurations that should be
  accessible in development in the app (e.g. endpoints), and switch them at
  runtime. The switch can happen either using scheme launch environment
  variables, or with a UI within the app.
- **In Release builds:** In case of release, you can only include the
  configuration that the release build is bound to, and not include the runtime
  logic for switching configurations by using compiler directives.

::: info Non-standard configurations
<!-- -->
While Tuist supports non-standard configurations and makes them easier to manage
compared to vanilla Xcode projects, you'll receive warnings if configurations
are not consistent throughout the dependency graph. This helps ensure build
reliability and prevents configuration-related issues.
<!-- -->
:::

## Generated projects

### Buildable folders

Tuist 4.62.0 added support for **buildable folders** (Xcode's synchronized
groups), a feature introduced in Xcode 16 to reduce merge conflicts.

While Tuist's wildcard patterns (e.g., `Sources/**/*.swift`) already eliminate
merge conflicts in generated projects, buildable folders offer additional
benefits:

- **Automatic synchronization**: Your project structure stays in sync with the
  file system—no regeneration needed when adding or removing files
- **AI-friendly workflows**: Coding assistants and agents can modify your
  codebase without triggering project regeneration
- **Simpler configuration**: Define folder paths instead of managing explicit
  file lists

We recommend adopting buildable folders instead of traditional `Target.sources`
and `Target.resources` attributes for a more streamlined development experience.

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

When installing Swift Package Manager dependencies on CI, we recommend using the
`--force-resolved-versions` flag to ensure deterministic builds:

```bash
tuist install --force-resolved-versions
```

This flag ensures that dependencies are resolved using the exact versions pinned
in `Package.resolved`, eliminating issues caused by non-determinism in
dependency resolution. This is particularly important on CI where reproducible
builds are critical.
