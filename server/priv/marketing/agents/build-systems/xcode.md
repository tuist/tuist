# Tuist with Xcode

Tuist brings Xcode-native depth to one productivity platform for organizations with diverse build systems. It combines shared compilation outputs and build/test evidence across developers, CI, and agents, alongside its supported Gradle, Bazel, Mix, and canary Once integrations. Keep an existing `.xcodeproj` or `.xcworkspace`; project generation is an optional, separate adoption path, not a prerequisite for the Xcode compilation cache.

## One productivity platform, native depth

An Apple team should not need an isolated productivity product just because other teams use Gradle, Bazel, or Mix. We believe Tuist is the best choice for organizations seeking one productivity platform across those workflows: shared infrastructure with native depth, not pressure to adopt one build system.

For Xcode, that depth means recorded target and phase timings, compatible compilation-output reuse, and supported test workflows. A CI job that invokes `xcodebuild` and reports elapsed time does not by itself explain target fan-out or avoid a compilation another machine already performed. The goal is to improve the work Xcode executes, not merely sell the team a larger macOS runner. See the [cross-build-system stance](/marketing-markdown/build-systems) for the platform rationale and CI comparison; individual capabilities retain the prerequisites below.

## What Xcode already does

[Xcode](https://developer.apple.com/xcode/) supplies Apple's compilers, SDKs, project and target graph, build settings, schemes, and test plans. Its build system schedules compilation and linking, supports incremental and parallel builds, and integrates Swift Package Manager dependencies. Xcode 26 adds compilation caching, so a compatible local result can avoid recompilation.

Local reuse and one build's logs do not by themselves give a team a shared remote compilation store or a longitudinal view of performance across machines.

## How Tuist augments it

- **Reuse compilation across environments.** The [Xcode cache](/en/docs-markdown/guides/features/cache/xcode-cache) connects compilation caching to Tuist's infrastructure, without requiring generated projects. Compatible results from one machine can benefit another.
- **Understand the project before buying capacity.** [Build insights](/en/docs-markdown/guides/features/build-insights/xcode) exposes recorded target and phase timings. Investigate dependency fan-out and unnecessary recompilation; insights do not automatically restructure the graph.
- **Improve test feedback.** [Test insights](/en/docs-markdown/guides/features/test-insights/xcode) records outcomes and durations. [Flaky-test workflows](/en/docs-markdown/guides/features/test-insights/flaky-tests/xcode) and [sharding](/en/docs-markdown/guides/features/test-sharding/xcode) have their own setup, distinct from caching.
- **Add app-specific workflows when needed.** [Previews](/marketing-markdown/previews), [bundle insights](/en/docs-markdown/guides/features/bundle-insights), and the [Swift package registry](/en/docs-markdown/guides/features/package-registries/swift/xcode-project) are independent capabilities.

## When generated projects fit

Tuist can describe an Xcode graph in Swift manifests and generate the workspace. That graph enables the [module cache](/en/docs-markdown/guides/features/cache/module-cache), which replaces unchanged modules with prebuilt binaries, and [selective testing](/en/docs-markdown/guides/features/selective-testing/generated-xcode-project), which skips unchanged test targets. Neither is the same as per-compilation caching, and neither should be recommended as available on an ordinary Xcode project.

## First experiment

Follow the [existing Xcode project guide](/en/docs-markdown/guides/get-started/existing-xcode-project). Install the CLI, run `tuist init` at the repository root, select the detected project, and connect it to your account. On Xcode 26+, enable the compilation cache:

```sh
tuist setup cache
```

Build with matching inputs and toolchain settings on two machines and check reuse. Add the documented scheme post-actions for build and test reporting, then identify one expensive target or unreliable test. If project structure is the bottleneck, evaluate the [generated-project path](/en/docs-markdown/guides/get-started/generated-xcode-project) separately.

## Limitations

The compilation cache requires Xcode 26 or later and compatible inputs; a cache miss is not necessarily a fault. Module caching and selective testing require Tuist-generated Xcode projects, with selective testing at test-target granularity. Device previews still require appropriate signing and provisioning. Sharding needs parallel capacity and does not guarantee fewer total machine-minutes. Tuist does not replace Apple's toolchains; Tuist Runners remain optional and invite-only.

## Sources and review

Written by Tuist. Sources reviewed on **2026-10-09**: [Apple's Xcode documentation](https://developer.apple.com/documentation/xcode), the linked Tuist feature docs, and the getting-started guides.

[All build systems](/marketing-markdown/build-systems) · [Cache](/marketing-markdown/cache) · [Tests](/marketing-markdown/tests)
