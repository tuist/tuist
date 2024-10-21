---
title: Migrate a Bazel project
description: Learn how to migrate your projects from Bazel to Tuist.
---

# Migrate a Bazel project

[Bazel](https://bazel.build) is a build system that Google open-sourced in 2015. It's a powerful tool that allows you to build and test software of any size, quickly and reliably. Some large organizations like [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae), or [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) use it, however, it requires an upfront (i.e., learning the technology) and ongoing investment (i.e., keeping up with Xcode updates) to introduce and maintain. While this works for some organizations that treat it as a cross-cutting concern, it might not be the best fit for others that want to focus on their product development. For instance, we've seen organizations whose iOS platform team introduced Bazel and had to drop it after the engineers that led the effort left the company. Apple's stance on the strong coupling between Xcode and the build system is another factor that makes it hard to maintain Bazel projects over time.

> [!TIP] TUIST UNIQUENESS LIES IN ITS FINESSE
> Instead of fighting Xcode and Xcode projects, Tuist embraces it. It's the same concepts (e.g., targets, schemes, build settings), a familiar language (i.e., Swift), and a simple and enjoyable experience that makes maintaining and scaling projects everyone's job and not just the iOS platform team's.

## Rules

Bazel uses rules to define how to build and test software. The rules are written in [Starlark](https://github.com/bazelbuild/starlark), a Python-like language. Tuist uses Swift as a configuration language, which provides developers with the convenience of using Xcode's autocompletion, type-checking, and validation features. For example, the following rule describes how to build a Swift library in Bazel:

::: code-group
```starlark [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
:::

Here's another example but compating how to define unit tests in Bazel and Tuist:

:::code-group
```starlark [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "io.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)

```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
:::


## Swift Package Manager dependencies

In Bazel, you can use the [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) plugin to use Swift Packages as dependencies. The plugin requires a `Package.swift` as a source of truth for the dependencies. Tuist's interface is similar to Bazel's in that sense. You can use the `tuist install` command to resolve and pull the dependencies of the package. After the resolution completes, you can then generate the project with the `tuist generate` command.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Project generation

The community provides a set of rules, [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj), to generate Xcode projects off Bazel-declared projects. Unlike Bazel, where you need to add some configuration to your `BUILD` file, Tuist doesn't require any configuration at all. You can run `tuist generate` in the root directory of your project, and Tuist will generate an Xcode project for you.