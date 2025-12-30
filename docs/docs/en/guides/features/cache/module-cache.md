---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---

# Module cache {#module-cache}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/features/projects">generated project</LocalizedLink>
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
<!-- -->
:::

Tuist Module cache provides a powerful way to optimize your build times by caching your modules as binaries (`.xcframework`s) and sharing them across different environments. This capability allows you to leverage previously generated binaries, reducing the need for repeated compilation and speeding up the development process.

## Warming {#warming}

Tuist efficiently <LocalizedLink href="/guides/features/projects/hashing">utilizes hashes</LocalizedLink> for each target in the dependency graph to detect changes. Utilizing this data, it builds and assigns unique identifiers to binaries derived from these targets. At the time of graph generation, Tuist then seamlessly substitutes the original targets with their corresponding binary versions.

This operation, known as *"warming,"* produces binaries for local use or for sharing with teammates and CI environments via Tuist. The process of warming the cache is straightforward and can be initiated with a simple command:


```bash
tuist cache
```

The command re-uses binaries to speed up the process.

## Usage {#usage}

By default, when Tuist commands necessitate project generation, they automatically substitute dependencies with their binary equivalents from the cache, if available. Additionally, if you specify a list of targets to focus on, Tuist will also replace any dependent targets with their cached binaries, provided they are available. For those who prefer a different approach, there is an option to opt out of this behavior entirely by using a specific flag:

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: warning
<!-- -->
Binary caching is a feature designed for development workflows such as running the app on a simulator or device, or running tests. It is not intended for release builds. When archiving the app, generate a project with the sources by using the `--no-binary-cache` flag.
<!-- -->
:::

## Cache profiles {#cache-profiles}

Tuist supports cache profiles to control how aggressively targets are replaced with cached binaries when generating projects.

- Built-ins:
  - `only-external`: replace external dependencies only (system default)
  - `all-possible`: replace as many targets as possible (including internal targets)
  - `none`: never replace with cached binaries

Select a profile with `--cache-profile` on `tuist generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely (backwards compatible)
tuist generate --no-binary-cache  # equivalent to --cache-profile none
```

Precedence when resolving the effective behavior (highest to lowest):

1. `--no-binary-cache` → profile `none`
2. Target focus (passing targets to `generate`) → profile `all-possible`
3. `--cache-profile <value>`
4. Config default (if set)
5. System default (`only-external`)

## Supported products {#supported-products}

Only the following target products are cacheable by Tuist:

- Frameworks (static and dynamic) that don't depend on [XCTest](https://developer.apple.com/documentation/xctest)
- Bundles
- Swift Macros

We are working on supporting libraries and targets that depend on XCTest.

::: info UPSTREAM DEPENDENCIES
<!-- -->
When a target is non-cacheable it makes the upstream targets non-cacheable too. For example, if you have the dependency graph `A > B`, where A depends on B, if B is non-cacheable, A will also be non-cacheable.
<!-- -->
:::

## Efficiency {#efficiency}

The level of efficiency that can be achieved with binary caching depends strongly on the graph structure. To achieve the best results, we recommend the following:

1. Avoid very nested dependency graphs. The shallower the graph, the better.
2. Define dependencies with protocol/interface targets instead of implementation ones, and dependency-inject implementations from the top-most targets.
3. Split frequently-modified targets into smaller ones whose likelihood of change is lower.

The above suggestions are part of the <LocalizedLink href="/guides/features/projects/tma-architecture">The Modular Architecture</LocalizedLink>, which we propose as a way to structure your projects to maximize the benefits not only of binary caching but also of Xcode's capabilities.

## Recommended setup {#recommended-setup}

We recommend having a CI job that **runs in every commit in the main branch** to warm the cache. This will ensure the cache always contains binaries for the changes in `main` so local and CI branch build incrementally upon them.

::: tip CACHE WARMING USES BINARIES
<!-- -->
The `tuist cache` command also makes use of the binary cache to speed up the warming.
<!-- -->
:::

The following are some examples of common workflows:

### A developer starts to work on a new feature {#a-developer-starts-to-work-on-a-new-feature}

1. They create a new branch from `main`.
2. They run `tuist generate`.
3. Tuist pulls the most recent binaries from `main` and generates the project with them.

### A developer pushes changes upstream {#a-developer-pushes-changes-upstream}

1. The CI pipeline will run `xcodebuild build` or `tuist test` to build or test the project.
2. The workflow will pull the most recent binaries from `main` and generate the project with them.
3. It will then build or test the project incrementally.

## Configuration {#configuration}

### Cache concurrency limit {#cache-concurrency-limit}

By default, Tuist downloads and uploads cache artifacts without any concurrency limit, maximizing throughput. You can control this behavior using the `TUIST_CACHE_CONCURRENCY_LIMIT` environment variable:

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

This can be useful in environments with limited network bandwidth or to reduce system load during cache operations.

## Troubleshooting {#troubleshooting}

### It doesn't use binaries for my targets {#it-doesnt-use-binaries-for-my-targets}

Ensure that the <LocalizedLink href="/guides/features/projects/hashing#debugging">hashes are deterministic</LocalizedLink> across environments and runs. This might happen if the project has references to the environment, for example through absolute paths. You can use the `diff` command to compare the projects generated by two consecutive invocations of `tuist generate` or across environments or runs.

Also make sure that the target doesn't depend either directly or indirectly on a <LocalizedLink href="/guides/features/cache/generated-project#supported-products">non-cacheable target</LocalizedLink>.

### Missing symbols {#missing-symbols}

When using sources, Xcode's build system, through Derived Data, can resolve dependencies that are not declared explicitly. However, when you rely on the binary cache, dependencies must be declared explicitly; otherwise you'll likely see compilation errors when symbols can't be found. To debug this, we recommend using the <LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect implicit-imports`</LocalizedLink> command and setting it up in CI to prevent regressions in implicit linking.
