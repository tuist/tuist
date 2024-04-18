---
title: Binary Caching
titleTemplate: ':title - Tuist Cloud'
description: Optimize your build times by caching compiled binaries and sharing them across different environments.
---

# Binary Caching

Xcode's build system is designed for [incremental builds](https://en.wikipedia.org/wiki/Incremental_build_model), enhancing efficiency under normal circumstances. However, this feature falls short in [Continuous Integration (CI) environments](https://en.wikipedia.org/wiki/Continuous_integration), where data essential for incremental builds is not shared across different builds. Additionally, **developers often reset this data locally to troubleshoot complex compilation problems**, leading to more frequent clean builds. This results in teams spending excessive time waiting for local builds to finish or for Continuous Integration pipelines to provide feedback on pull requests. Furthermore, the frequent context switching in such an environment compounds this unproductiveness.

Tuist addresses these challenges effectively with its binary caching feature. This tool optimizes the build process by caching compiled binaries, significantly reducing build times both in local development and CI environments. This approach not only accelerates feedback loops but also minimizes the need for context switching, ultimately boosting productivity.

> [!NOTE] BINARY CACHING AND TUIST SUSTAINABILITY
> Be aware that sharing binaries across environments is not possible without Tuist Cloud. We've designed this feature to secure funding for the Tuist projct, which we couldn't achieve with the traditional open-source model. Attempts to work around this limitation may impact the sustainability of the project, which might impact your ability to use Tuist in the future.

## Cache warming

Tuist efficiently utilizes **hashes** for each target in the dependency graph to detect changes. Utilizing this data, it builds and assigns unique identifiers to binaries derived from these targets. At the time of graph generation, Tuist then seamlessly substitutes the original targets with their corresponding binary versions.

This operation, known as *"warming,"* produces binaries for local use or for sharing with teammates and CI environments via Tuist Cloud. The process of warming the cache is straightforward and can be initiated with a simple command:


```bash
tuist cache
```

The command re-uses binaries to speed up the process.

> [!TIP] CACHE WARMING IN CI ENVIRONMENTS 
> We recommend setting up a CI pipeline exclusively to keep the cache warmed. That way developers in your team will have access to those binaries, thereby reducing their local build times.

## Using the cache binaries

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

## Cacheable products

Only the following target products are cacheable by Tuist:

- Frameworks (static and dynamic) that don't depend on [XCTest](https://developer.apple.com/documentation/xctest)
- Bundles
- Swift Macros

We are working on supporting libraries and targets that depend on XCTest.

> [!NOTE] UPSTREAM DEPENDENCIES
> When a target is non-cacheable it makes the upstream targets non-cacheable too. For example, if you have the dependency graph `A > B`, where A depends on B, if B is non-cacheable, A will also be non-cacheable.

## Hashing

The hash of a target is calculated by hashing its attributes, the files the target depends on, and the hashes of its dependencies. The current hashing logic is a bit opaque, but we are working on improving it to make it more transparent and predictable. We also have plans to expose APIs such that you can customize the hashing logic to suit your needs. For example, you could instruct Tuist to hash an environment variable that has an impact on the target's output.

## Cache effectiveness

The level of effectiveness that can be achieved with binary caching depends strongly on the graph structure. To achieve the best results, we recommend the following:

1. Avoid very nested dependency graphs. The shallower the graph, the better.
2. Define dependencies with protocol/interface targets instead of implementation ones, and dependency-inject implementations from the top-most targets.
3. Split frequently-modified targets into smaller ones whose likelihood of change is lower.

The above suggestions are part of the [µFeatures architecture](/guide/scale/ufeatures-architecture), which we propose as a way to structure your projects to maximize the benefits not only of binary caching but also of Xcode's capabilities.