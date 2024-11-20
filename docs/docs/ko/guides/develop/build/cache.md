---
title: Cache
titleTemplate: :title · Build · Develop · Guides · Tuist
description: 컴파일된 바이너리를 캐싱하고 다양한 환경 간에 공유하여 빌드 시간을 최적화 하세요.
---

# Cache {#cache}

> [!IMPORTANT] REMOTE PROJECT 필요
> 이 기능은 <LocalizedLink href="/server/introduction/accounts-and-projects">remote project</LocalizedLink>가 필요합니다.

Xcode의 빌드 시스템은 [증분 빌드](https://en.wikipedia.org/wiki/Incremental_build_model)를 제공하여 일반적인 상황에서 효율을 높입니다. 하지만 이 기능은 증분 빌드에 필요한 데이터가 서로 다른 빌드에서 공유되지 않으므로, [Continuous Integration (CI) 환경](https://en.wikipedia.org/wiki/Continuous_integration)에서는 적절하지 않습니다. 게다가 **개발자는 복잡한 컴파일 문제를 해결하기 위해 로컬에서 이 데이터를 초기화 하므로**, 클린 빌드가 자주 발생하게 됩니다. 팀은 이것으로 인해 로컬 빌드가 완료되거나 Continuous Integration 파이프라인이 Pull Request에 대한 피드백을 제공할 때까지 과도한 시간을 기다려야 합니다. 더욱이 이러한 환경에서 빈번한 컨텍스트 전환은 생산성을 더욱 악화시킵니다.

Tuist는 캐싱 기능으로 이 문제를 효과적으로 해결합니다. 이 툴은 컴파일된 바이너리를 캐시 하여 빌드 과정을 최적화하고, 로컬 개발 환경과 CI 환경 모두에서 빌드 시간을 크게 단축 시킵니다. 이 접근 방식은 피드백 순환을 가속화할 뿐만 아니라 컨텍스트 전환을 최소화하여 생산성을 극대화합니다.

## 워밍 {#warming}

Tuist는 각 타겟에 대한 의존성 그래프 변화를 감지하기 위해 효율적으로 <LocalizedLink href="/guides/develop/projects/hashing">해시를 활용합니다.</LocalizedLink> 이 데이터를 활용하여, Tuist는 타겟의 바이너리에 고유 식별자를 생성하고 할당합니다. At the time of graph generation, Tuist then seamlessly substitutes the original targets with their corresponding binary versions.

This operation, known as _"warming,"_ produces binaries for local use or for sharing with teammates and CI environments via Tuist. The process of warming the cache is straightforward and can be initiated with a simple command:

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

:::

> [!WARNING]
> Binary caching is a feature designed for development workflows such as running the app on a simulator or device, or running tests. It is not intended for release builds. When archiving the app, generate a project with the sources by using the `--no-binary-cache` flag.

## Supported products {#supported-products}

Only the following target products are cacheable by Tuist:

- Frameworks (static and dynamic) that don't depend on [XCTest](https://developer.apple.com/documentation/xctest)
- Bundles
- Swift Macros

We are working on supporting libraries and targets that depend on XCTest.

> [!NOTE] UPSTREAM DEPENDENCIES
> When a target is non-cacheable it makes the upstream targets non-cacheable too. For example, if you have the dependency graph `A > B`, where A depends on B, if B is non-cacheable, A will also be non-cacheable.

## Efficiency {#efficiency}

The level of efficiency that can be achieved with binary caching depends strongly on the graph structure. To achieve the best results, we recommend the following:

1. Avoid very nested dependency graphs. The shallower the graph, the better.
2. Define dependencies with protocol/interface targets instead of implementation ones, and dependency-inject implementations from the top-most targets.
3. Split frequently-modified targets into smaller ones whose likelihood of change is lower.

The above suggestions are part of the <LocalizedLink href="/guides/develop/projects/tma-architecture">The Modular Architecture</LocalizedLink>, which we propose as a way to structure your projects to maximize the benefits not only of binary caching but also of Xcode's capabilities.

## Recommended setup {#recommended-setup}

We recommend having a CI job that **runs in every commit in the main branch** to warm the cache. This will ensure the cache always contains binaries for the changes in `main` so local and CI branch build incrementally upon them.

> [!TIP] CACHE WARMING USES BINARIES
> The `tuist cache` command also makes use of the binary cache to speed up the warming.

The following are some examples of common workflows:

### A developer starts to work on a new feature {#a-developer-starts-to-work-on-a-new-feature}

1. They create a new branch from `main`.
2. They run `tuist generate`.
3. Tuist pulls the most recent binaries from `main` and generates the project with them.

### A developer pushes changes upstream {#a-developer-pushes-changes-upstream}

1. The CI pipeline will run `tuist build` or `tuist test` to build or test the project.
2. The workflow will pull the most recent binaries from `main` and generate the project with them.
3. It will then build or test the project incrementally.

## Troubleshooting {#troubleshooting}

### It doesn't use binaries for my targets {#it-doesnt-use-binaries-for-my-targets}

Ensure that the <LocalizedLink href="/guides/develop/projects/hashing#debugging">hashes are deterministic</LocalizedLink> across environments and runs. This might happen if the project has references to the environment, for example through absolute paths. You can use the `diff` command to compare the projects generated by two consecutive invocations of `tuist generate` or across environments or runs.

Also make sure that the target doesn't depend either directly or indirectly on a <LocalizedLink href="/guides/develop/build/cache.html#cacheable-products">non-cacheable target</LocalizedLink>.
