---
title: Dependencies
description: Learn how to declare dependencies in your Tuist project.
---

# Dependencies

When a project grows, it's common to split it into multiple targets to share code, define boundaries, and improve build times.
Multiple targets means defining dependencies between them forming a **dependency graph**, which might include external dependencies as well.

## XcodeProj-codified graphs

Due to Xcode and XcodeProj's design,
the maintenance of a dependency graph can be a tedious and error-prone task.
Here are some examples of the problems that you might encounter:

- Because Xcode's build system outputs all the project's products into the same directory in derived data, targets might be able to import products that they shouldn't. Compilations might fail on CI, where clean builds are more common, or later on when a different configuration is used.
- The transitive dynamic dependencies of a target need to be copied into any of the directories that are part of the `LD_RUNPATH_SEARCH_PATHS` build setting. If they aren't, the target won't be able to find them at runtime. This is easy to think about and set up when the graph is small, but it becomes a problem as the graph grows.
- When a target links a static [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle), the target needs an additional build phase for Xcode to process the bundle and extract the right binary for the current platform and architecture. This build phase is not added automatically, and it's easy to forget to add it.

The above are just a few examples, but there are many more that we've encountered over the years.
Imagine if you required a team of engineers to maintain a dependency graph and ensure its validity.
Or even worse,
that the intricacies were resolved at build-time by a closed-source build system that you can't control or customize.
Sounds familiar? This is the approach that Apple took with Xcode and XcodeProj and that the Swift Package Manager has inherited.

We strongly believe that the dependency graph should be **explicit** and **static** because only then can it be **validated** and **optimized**.
With Tuist, you focus on describing what depends on what, and we take care of the rest.
The intricacies and implementation details are abstracted away from you.

In the following sections you'll learn how to declare dependencies in your project.

> [!TIP] GRAPH VALIDATION
> Tuist validates the graph when generating the project to ensure that there are no cycles and that all the dependencies are valid. Thanks to this, any team can take part in evolving the dependency graph without worrying about breaking it.

## Local dependencies

Targets can depend on other targets in the same and different projects, and on binaries.
When instantiating a `Target`, you can pass the `dependencies` argument with any of the following options:

- `Target`: Declares a dependency with a target within the same project.
- `Project`: Declares a dependency with a target in a different project.
- `Framework`: Declares a dependency with a binary framework.
- `Library`: Declares a dependency with a binary library.
- `XCFramework`: Declares a dependency with a binary XCFramework.
- `SDK`: Declares a dependency with a system SDK.
- `XCTest`: Declares a dependency with XCTest.

> [!NOTE] DEPENDENCY CONDITIONS
> Every dependency type accepts a `condition` option to conditionally link the dependency based on the platform. By default, it links the dependency for all platforms the target supports.

> [!TIP] ENFORCING EXPLICIT DEPENDENCIES
> We have an experimental feature to enforce explicit dependencies in Xcode. We recommend enabling it to ensure targets can only import the dependencies that they've explicitly declared.
> ```swift
> import ProjectDescription
> let config = Config(generationOptions: .options(enforceExplicitDependencies: true))
> ```
<!-- > Warning: We haven't yet solved the problem of targets being able to import dependencies that they shouldn't. Some users have implemented their custom solutions to detect this, but we haven't yet found a solution that we're happy with. We are currently exploring customizing the directory where products are outputted to solve this problem. -->

## External dependencies

Tuist also allows you to declare external dependencies in your project.

### Swift Packages

Swift Packages are our recommended way of declaring dependencies in your project.
You can integrate them using Xcode's default integration mechanism or using Tuist's XcodeProj-based integration.

#### Tuist's XcodeProj-based integration

Xcode's default integration while being the most convenient one,
lacks flexibility and control that's required for medium and large projects.
To overcome this, Tuist offers an XcodeProj-based integration that allows you to integrate Swift Packages in your project using XcodeProj's targets.
Thanks to that, we can not only give you more control over the integration but also make it compatible with workflows like [binary caching](/cloud/binary-caching) and [selective testing](/cloud/selective-testing).

XcodeProj's integration is more likely to take more time to support new Swift Package features or handle more package configurations. However, the mapping logic between Swift Packages and XcodeProj targets is open-source and can be contributed to by the community. This is contrary to Xcode's default integration, which is closed-source and maintained by Apple.

To add external dependencies, you'll have to create a `Package.swift` either under `Tuist/` or at the root of the project.

::: code-group
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),

    ]
)
```
:::

> [!TIP] PACKAGE SETTINGS
> The `PackageSettings` instance wrapped in a compiler directive allows you to configure how packages are integrated. For example, in the example above it's used to override the default product type used for packages. By default, you shouldn't need it.

The `Package.swift` file is just an interface to declare external dependencies, nothing else. That's why you don't define any targets or products in the package. Once you have the dependencies defined, you can run the following command to resolve and pull the dependencies into the `Tuist/Dependencies` directory:

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

As you might have noticed, we take an approach similar to [CocoaPods](https://cocoapods.org)', where the resolution of dependencies is its own command. This gives control to the users over when they'd like dependencies to be resolved and updated, and allows opening the Xcode in project and have it ready to compile. This is an area where we believe the developer experience provided by Apple's integration with the Swift Package Manager degrates over time as the project grows.

From your project targets you can then reference those dependencies using the `TargetDependency.external` dependency type:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
:::

> [!NOTE] NO SCHEMES GENERATED FOR EXTERNAL PACKAGES
> The **schemes** are not automatically created for Swift Package projects to keep the schemes list clean. You can create them via Xcode's UI.

#### Xcode's default integration

If you want to use Xcode's default integration mechanism, you can pass the list `packages` when instantiating a project:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

And then reference them from your targets:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

For Swift Macros and Build Tool Plugins, you'll need to use the types `.macro` and `.plugin` respectively.

### Carthage

Since [Carthage](https://github.com/carthage/carthage) outputs `frameworks` or `xcframeworks`, you can run `carthage update` to output the dependencies in the `Carthage/Build` directory and then use the `.framework` or `.xcframework` target dependency type to declare the dependency in your target. You can wrap this in a script that you can run before generating the project.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING] BUILD AND TEST
> If you build and test your project through `tuist build` and `tuist test`, you will similarly need to ensure that the Carthage-resolved dependencies are present by running the `carthage update` command before `tuist build` or `tuist test` are run.

### CocoaPods

[CocoaPods](https://cocoapods.org) expects an Xcode project to integrate the dependencies. You can use Tuist to generate the project, and then run `pod install` to integrate the dependencies by creating a workspace that contains your project and the Pods dependencies. You can wrap this in a script that you can run before generating the project.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods dependencies are not compatible with workflows like `build` or `test` that run `xcodebuild` right after generating the project. They are also incompatible with binary caching and selective testing since the fingerprinting logic doesn't account for the Pods dependencies.

## Troubleshooting

### Objective-C Dependencies

When integrating Objective-C dependencies, the inclusion of certain flags on the consuming target may be necessary to avoid runtime crashes as detailed in [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Since the build system and Tuist have no way of inferring whether the flag is necessary or not, and since the flag comes with potentially undesirable side effects, Tuist will not automatically apply any of these flags, and because Swift Package Manager considers `-ObjC` to be included via an `.unsafeFlag` most packages cannot include it as part of their default linking settings when required.

Consumers of Objective-C dependencies (or internal Objective-C targets) should apply `-ObjC` or `-force_load` flags when required by setting `OTHER_LDFLAGS` on consuming targets.

### Firebase & Other Google Libraries

Google's open source libraries — while powerful — can be difficult to integrate within Tuist as they often use non-standard architecture and techniques in how they are built.

Here are a few tips that may be necessary to follow to integrate Firebase and Google's other Apple-platform libraries:

#### Ensure `-ObjC` is added to `OTHER_LDFLAGS`

Many of Google's libraries are written in Objective-C. Because of this, any consuming target will need to include the `-ObjC` tag in its `OTHER_LDFLAGS` build setting. This can either be set in an `.xcconfig` file or manually specified in the target's settings within your Tuist manifests. An example:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Refer to the [Objective-C Dependencies](#objective-c-dependencies) section above for more details.

#### Set the product type for `FBLPromises` to dynamic framework

Certain Google libraries depend on `FBLPromises`, another of Google's libraries. You may encounter a crash that mentions `FBLPromises`, looking something like this:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Explicitly setting the product type of `FBLPromises` to `.framework` in your `Package.swift` file should fix the issue:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FPLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```
