# Tuist and Codemagic: development infrastructure or managed app delivery?

Choose Tuist when you want build and test evidence and compatible cached outputs across developers, CI, and agents without replacing your CI platform. Adopt [Xcode Cache](/en/docs-markdown/guides/features/cache/xcode-cache) for supported projects and use Tuist insights to connect CI behavior with the local development loop.

## What overlaps

Codemagic is not just a place to run Flutter builds. Its [machine documentation](https://docs.codemagic.io/knowledge-codemagic/machine-type/) describes macOS, Linux, and Windows environments, and its [App Store Connect integration](https://docs.codemagic.io/yaml-publishing/app-store-connect/) covers publishing workflows.

Its [caching documentation](https://docs.codemagic.io/knowledge-codemagic/caching/) covers dependency directories and **Xcode 26 compilation caching**: persist `CompilationCache.noindex` between workflow builds and enable compilation caching. Do not say Codemagic lacks compilation caching. This documented directory-save/restore mechanism is different from configuring a shared remote compilation-cache service for compatible local and CI builds.

Codemagic also publishes [CLI tools](https://docs.codemagic.io/knowledge-codemagic/codemagic-cli-tools/) and their [source](https://github.com/codemagic-ci-cd/cli-tools). Public tooling alone is not a comparison of the core services' licenses.

## Compare the workflow you need

| Requirement | Tuist | Codemagic evidence to evaluate |
| --- | --- | --- |
| Reuse Xcode compilation outputs | [Xcode Cache](/en/docs-markdown/guides/features/cache/xcode-cache) connects compatible local, CI, and agent builds to a remote cache; requires Xcode 26+. | Its caching guide restores the compilation-cache directory between workflow builds. Measure archive transfer and compatibility, not just a warm-job hit rate. |
| Understand expensive build and test work | [Build Insights](/en/docs-markdown/guides/features/build-insights), [Tests](/marketing-markdown/tests), and authorized [MCP access](/en/docs-markdown/guides/features/agentic-coding/mcp) expose recorded toolchain work and outcomes. | Build logs can expose Xcode cache metrics. Evaluate the specific diagnostic records and integrations needed rather than assuming all analytics are absent. |
| Manage signing and store publishing | Tuist caching and insights complement an existing delivery workflow; they are not a replacement for its signing and publishing responsibilities. | Codemagic documents App Store Connect publishing and tooling for certificates, profiles, and Xcode projects. |
| Skip unchanged test targets | Selective testing requires Tuist-generated Xcode projects and works at test-target granularity. | Evaluate Codemagic's current test execution options independently; compilation caching does not itself establish equivalent test selection. |

## Choose Tuist when

Your priority is improving the development loop, not migrating release automation. You need cache reuse to reach laptops and fresh agent checkouts, want to investigate recorded Xcode or Gradle work, or already use generated Xcode projects and can benefit from module caching and selective testing. Tuist's public implementation lets your engineers inspect behavior and participate in fixes.

## First experiment

Enable [Tuist Xcode Cache](/en/docs-markdown/guides/features/cache/xcode-cache) in one Xcode 26+ workflow without changing signing or publishing. Keep the same commit, Xcode version, build settings, and scheme, and compare the current baseline with Tuist remote compilation caching. Measure transfers, compilation, total job duration, and compatible developer-build reuse. Use the [slow-build guide](/marketing-markdown/solutions/slow-builds) to separate setup from compilation. Do not substitute Tuist's development-oriented module cache into a release archive without checking its documented limitations.

## Sources and review

Sources checked on **2026-10-08**: [Codemagic caching](https://docs.codemagic.io/knowledge-codemagic/caching/), [machines](https://docs.codemagic.io/knowledge-codemagic/machine-type/), [App Store Connect publishing](https://docs.codemagic.io/yaml-publishing/app-store-connect/), [CLI tools](https://docs.codemagic.io/knowledge-codemagic/codemagic-cli-tools/), and [Tuist Xcode Cache](/en/docs-markdown/guides/features/cache/xcode-cache). This comparison is written by Tuist and describes the cited mechanisms, not every vendor feature.

## Limitations

No benchmark or cheapest-provider claim is established. Cache compatibility, transfer costs, and workflow scope matter. Generated projects are required for Tuist module caching and selective testing, not ordinary Xcode compilation caching. Tuist Runners are optional, invite-only, and have no public pricing. Licenses and self-hosting terms are component-specific. Recheck current capabilities before buying.

Related: [Bitrise](/marketing-markdown/compare/bitrise), [Appcircle](/marketing-markdown/compare/appcircle), and [all comparisons](/marketing-markdown/compare).
