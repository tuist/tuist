---
title: Cache
description: Optimize your build times by caching compiled binaries and sharing them across different environments.
---

# Cache

> [!IMPORTANT] REQUIRES AN ACCOUNT
> You need to be authenticated and have and [a project set up](/guides/quick-start/gather-insights) to persist and share the cache across environments.

Xcode's build system provides [incremental builds](https://en.wikipedia.org/wiki/Incremental_build_model), enhancing efficiency under normal circumstances. However, this feature falls short in [Continuous Integration (CI) environments](https://en.wikipedia.org/wiki/Continuous_integration), where data essential for incremental builds is not shared across different builds. Additionally, **developers often reset this data locally to troubleshoot complex compilation problems**, leading to more frequent clean builds. This results in teams spending excessive time waiting for local builds to finish or for Continuous Integration pipelines to provide feedback on pull requests. Furthermore, the frequent context switching in such an environment compounds this unproductiveness.

Tuist addresses these challenges effectively with its caching feature. This tool optimizes the build process by caching compiled binaries, significantly reducing build times both in local development and CI environments. This approach not only accelerates feedback loops but also minimizes the need for context switching, ultimately boosting productivity.

## Warming

Tuist efficiently [utilizes hashes](/guides/develop/projects/hashing) for each target in the dependency graph to detect changes. Utilizing this data, it builds and assigns unique identifiers to binaries derived from these targets. At the time of graph generation, Tuist then seamlessly substitutes the original targets with their corresponding binary versions.

This operation, known as *"warming,"* produces binaries for local use or for sharing with teammates and CI environments via Tuist. The process of warming the cache is straightforward and can be initiated with a simple command:


```bash
tuist cache
```

The command re-uses binaries to speed up the process.

## Usage

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
:::

> [!WARNING]
> Binary caching is a feature designed for development workflows such as running the app on a simulator or device, or running tests. It is not intended for release builds. When archiving the app, generate a project with the sources by using the `--no-binary-cache` flag.

## Supported products

Only the following target products are cacheable by Tuist:

- Frameworks (static and dynamic) that don't depend on [XCTest](https://developer.apple.com/documentation/xctest)
- Bundles
- Swift Macros

We are working on supporting libraries and targets that depend on XCTest.

> [!NOTE] UPSTREAM DEPENDENCIES
> When a target is non-cacheable it makes the upstream targets non-cacheable too. For example, if you have the dependency graph `A > B`, where A depends on B, if B is non-cacheable, A will also be non-cacheable.

## Efficiency

The level of efficiency that can be achieved with binary caching depends strongly on the graph structure. To achieve the best results, we recommend the following:

1. Avoid very nested dependency graphs. The shallower the graph, the better.
2. Define dependencies with protocol/interface targets instead of implementation ones, and dependency-inject implementations from the top-most targets.
3. Split frequently-modified targets into smaller ones whose likelihood of change is lower.

The above suggestions are part of the [The Modular Architecture](/guides/develop/projects/tma-architecture), which we propose as a way to structure your projects to maximize the benefits not only of binary caching but also of Xcode's capabilities.

## Recommended setup

We recommend having a CI job that **runs in every commit in the main branch** to warm the cache. This will ensure the cache always contains binaries for the changes in `main` so local and CI branch build incrementally upon them.

> [!TIP] CACHE WARMING USES BINARIES
> The `tuist cache` command also makes use of the binary cache to speed up the warming.

The following are some examples of common workflows:

### A developer starts to work on a new feature

1. They create a new branch from `main`.
2. They run `tuist generate`.
3. Tuist pulls the most recent binaries from `main` and generates the project with them.

### A developer pushes changes upstream

1. The CI pipeline will run `tuist build` or `tuist test` to build or test the project.
2. The workflow will pull the most recent binaries from `main` and generate the project with them.
3. It will then build or test the project incrementally.

## Troubleshooting

### It doesn't use binaries for my targets

Ensure that the [hashes are deterministic](/guides/develop/projects/hashing#debugging) across environments and runs. This might happen if the project has references to the environment, for example through absolute paths. You can use the `diff` command to compare the projects generated by two consecutive invocations of `tuist generate` or across environments or runs.

Also make sure that the target doesn't depend either directly or indirectly on a [non-cacheable target](/guides/develop/build/cache.html#cacheable-products).