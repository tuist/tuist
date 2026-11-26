# Swift Package Manager vs Tuist: modularize with SPM or a Tuist project

Compare Swift Package Manager (SPM) and Tuist for a modular Xcode app: what each one describes, how they work together, and what Tuist adds to your builds either way.

## What is Swift Package Manager?

[Swift Package Manager](https://github.com/swiftlang/swift-package-manager) is Swift's open-source package manager, licensed under Apache 2.0 with a Runtime Library Exception. It resolves and versions dependencies, builds packages on macOS, Linux, and [Windows](https://www.swift.org/install/windows/), and has been [integrated into Xcode](https://developer.apple.com/documentation/xcode/swift-packages) since Xcode 11, so apps can depend on packages. A package is described in Swift, in a `Package.swift` manifest that declares its targets, products, and dependencies. Beyond third-party dependencies, many teams split an app into [local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages) and keep a thin Xcode project for the app target, its extensions, and their signing and build phases.

## What is Tuist?

Tuist is build infrastructure for engineering teams and coding agents: a shared environment where developers, CI, and coding agents build and test. It is not a CI provider or a coding agent: it works with the CI you already use, and [Tuist Runners](/marketing-markdown/runners) can run those jobs on managed macOS and Linux machines next to the cache. Many Apple developers first met Tuist through generated projects: you describe projects in Swift [manifests](/en/docs-markdown/guides/features/projects/manifests) such as `Project.swift`, and `tuist generate` produces the Xcode projects and workspace. Generation is one Tuist capability. The Xcode cache, build and test insights, and previews work with the Xcode project you already have.

## Describing modules: Package.swift or Project.swift

This is where the tools overlap, and both use Swift. With local packages, each module is a package target in the vocabulary of packages: targets, products, and platforms. Xcode resolves the packages and builds them alongside the app's Xcode project, where app targets, extensions, schemes, and build phases still live.

A Tuist manifest uses Xcode's own vocabulary, so the whole app, including app targets, extensions, schemes, and build phases, is described in one place. Tuist [validates the dependency graph](/en/docs-markdown/guides/features/projects/dependencies) when it generates the project, rejecting cycles and invalid dependencies, and reuses conventions through [project description helpers](/en/docs-markdown/guides/features/projects/code-sharing). The explicit graph is also what the [module cache](/en/docs-markdown/guides/features/cache/module-cache) and [selective testing](/en/docs-markdown/guides/features/selective-testing) use to hash targets, which is the practical reason to describe the app in Tuist rather than only the choice of manifest.

## Use both: SPM for dependencies

Tuist does not replace Swift Package Manager as a dependency manager; it uses it. There are two ways to [integrate packages](/en/docs-markdown/guides/features/projects/dependencies). With Tuist's XcodeProj-based integration, you declare third-party packages in `Tuist/Package.swift` and run `tuist install`, which resolves and fetches them with Swift Package Manager; Tuist then maps them to Xcode targets so they work with the module cache and selective testing. Tuist's integration is open source and can take longer to support new package features than Xcode's own. With Xcode's default integration, you list packages in the project's `packages` and Xcode resolves them, as it would in a project you maintain by hand. Build tool plugins need Xcode's default integration, even in a project that uses Tuist's for everything else.

The [Tuist Swift package registry](/en/docs-markdown/guides/features/package-registries/swift) speeds up package resolution whether packages are integrated by Tuist, by Xcode, or used from a standalone Swift package.

## Keep your packages, add Tuist

| What you need | Tuist capability | With an Xcode project that uses Swift packages |
| --- | --- | --- |
| Stop recompiling code another machine already compiled | [Xcode cache](/en/docs-markdown/guides/features/cache/xcode-cache) shares Xcode's compilation outputs across developer machines, CI, and agents | Yes, with Xcode 26 or later |
| See where build time goes and when it regressed | [Build insights](/en/docs-markdown/guides/features/build-insights) records every build's duration, steps, and cache results | Yes |
| Find slow and flaky tests | [Test insights](/en/docs-markdown/guides/features/test-insights) and [flaky-test detection](/en/docs-markdown/guides/features/test-insights/flaky-tests) keep a shared test history | Yes |
| Resolve packages faster | The [Swift package registry](/en/docs-markdown/guides/features/package-registries/swift) serves packages from Tuist's cache network | Yes |
| Skip unchanged modules entirely | The [module cache](/en/docs-markdown/guides/features/cache/module-cache) replaces unchanged targets with prebuilt binaries | Requires a Tuist generated project |
| Run only the tests a change affects | [Selective testing](/en/docs-markdown/guides/features/selective-testing) skips unchanged test targets | Requires a Tuist generated project |

To connect your existing project, follow the [existing Xcode project guide](/en/docs-markdown/guides/get-started/existing-xcode-project).

## When to move modules into Tuist

Move when the module cache or selective testing would remove work your team repeats today, or when keeping the app's targets, schemes, and module conventions consistent across many packages has become a job of its own. The [Swift package migration guide](/en/docs-markdown/guides/features/projects/adoption/migrate/swift-package) shows how `Package.swift` targets map to a `Project.swift`, and you can [try Tuist on an existing package](/en/docs-markdown/guides/features/projects/adoption/swift-package) by generating an Xcode project from it without changing it. Third-party dependencies stay in Swift Package Manager.

## First experiment

Keep your packages as they are. Record a clean build, the same build on a second machine, and a full test run. Connect the [Xcode cache](/en/docs-markdown/guides/features/cache/xcode-cache), [build insights](/en/docs-markdown/guides/features/build-insights), and [test insights](/en/docs-markdown/guides/features/test-insights), then repeat the same runs and compare feedback time, total machine usage, and which targets the cache served.

## Frequently asked questions

### Does Tuist replace Swift Package Manager?

No. Tuist uses Swift Package Manager to resolve and fetch dependencies declared in `Tuist/Package.swift`. What Tuist can replace is using local packages to describe the app's own modules, by describing them in `Project.swift` instead.

### Can I use Tuist without generated projects?

Yes. The Xcode cache, build insights, test insights, flaky-test detection, previews, and the Swift package registry work with an existing Xcode project. The module cache and selective testing require a Tuist generated project.

### Can a Tuist project depend on Swift packages?

Yes. For Tuist's XcodeProj-based integration, declare them in `Tuist/Package.swift` and run `tuist install`; libraries, macros, and other products it maps to Xcode targets then work with the module cache and selective testing. For Xcode's default integration, list them in the project's `packages`. Build tool plugins need Xcode's default integration.

### Can I generate an Xcode project from a Package.swift?

Yes, as a beta meant for assessing Tuist. Run `tuist install` and `tuist generate` in a package's directory to get a native Xcode project. It does not support every Swift Package Manager feature.

### Are Swift Package Manager and Tuist open source?

Yes. Swift Package Manager is licensed under Apache 2.0 with a Runtime Library Exception, and the Tuist CLI is MIT licensed. Tuist's server features, such as the remote cache and insights, run as a hosted service, and organizations on the Enterprise plan can self-host them.

## Sources and review

Sources checked on **2026-11-15**. Written by Tuist, not an independent benchmark. Swift Package Manager facts come from its [repository](https://github.com/swiftlang/swift-package-manager), the [Swift.org guide](https://www.swift.org/documentation/package-manager/), and Apple's documentation on [Swift packages](https://developer.apple.com/documentation/xcode/swift-packages) and [local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages). Tuist facts come from the linked documentation. No benchmarks, customer results, or prices are implied.

Explore [Cache](/marketing-markdown/cache), [Tests](/marketing-markdown/tests), [XcodeGen vs Tuist](/marketing-markdown/compare/xcodegen), [documentation](/en/docs-markdown/guides/get-started), [pricing](/marketing-markdown/pricing), and [all comparisons](/marketing-markdown/compare).
