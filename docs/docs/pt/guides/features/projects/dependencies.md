---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# Dependencies {#dependencies}

When a project grows, it's common to split it into multiple targets to share
code, define boundaries, and improve build times. Multiple targets means
defining dependencies between them forming a **dependency graph**, which might
include external dependencies as well.

## XcodeProj-codified graphs {#xcodeprojcodified-graphs}

Due to Xcode and XcodeProj's design, the maintenance of a dependency graph can
be a tedious and error-prone task. Here are some examples of the problems that
you might encounter:

- Because Xcode's build system outputs all the project's products into the same
  directory in derived data, targets might be able to import products that they
  shouldn't. Compilations might fail on CI, where clean builds are more common,
  or later on when a different configuration is used.
- The transitive dynamic dependencies of a target need to be copied into any of
  the directories that are part of the `LD_RUNPATH_SEARCH_PATHS` build setting.
  If they aren't, the target won't be able to find them at runtime. This is easy
  to think about and set up when the graph is small, but it becomes a problem as
  the graph grows.
- When a target links a static
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle),
  the target needs an additional build phase for Xcode to process the bundle and
  extract the right binary for the current platform and architecture. This build
  phase is not added automatically, and it's easy to forget to add it.

The above are just a few examples, but there are many more that we've
encountered over the years. Imagine if you required a team of engineers to
maintain a dependency graph and ensure its validity. Or even worse, that the
intricacies were resolved at build-time by a closed-source build system that you
can't control or customize. Sounds familiar? This is the approach that Apple
took with Xcode and XcodeProj and that the Swift Package Manager has inherited.

We strongly believe that the dependency graph should be **explicit** and
**static** because only then can it be **validated** and **optimized**. With
Tuist, you focus on describing what depends on what, and we take care of the
rest. The intricacies and implementation details are abstracted away from you.

In the following sections you'll learn how to declare dependencies in your
project.

::: tip GRAPH VALIDATION
<!-- -->
Tuist validates the graph when generating the project to ensure that there are
no cycles and that all the dependencies are valid. Thanks to this, any team can
take part in evolving the dependency graph without worrying about breaking it.
<!-- -->
:::

## Local dependencies {#local-dependencies}

Targets can depend on other targets in the same and different projects, and on
binaries. When instantiating a `Target`, you can pass the `dependencies`
argument with any of the following options:

- `Target`: Declares a dependency with a target within the same project.
- `Project`: Declares a dependency with a target in a different project.
- `Framework`: Declares a dependency with a binary framework.
- `Library`: Declares a dependency with a binary library.
- `XCFramework`: Declares a dependency with a binary XCFramework.
- `SDK`: Declares a dependency with a system SDK.
- `XCTest`: Declares a dependency with XCTest.

::: info DEPENDENCY CONDITIONS
<!-- -->
Every dependency type accepts a `condition` option to conditionally link the
dependency based on the platform. By default, it links the dependency for all
platforms the target supports.
<!-- -->
:::

## External dependencies {#external-dependencies}

Tuist also allows you to declare external dependencies in your project.

### Swift Packages {#swift-packages}

Swift Packages are our recommended way of declaring dependencies in your
project. You can integrate them using Xcode's default integration mechanism or
using Tuist's XcodeProj-based integration.

#### Tuist's XcodeProj-based integration {#tuists-xcodeprojbased-integration}

Xcode's default integration while being the most convenient one, lacks
flexibility and control that's required for medium and large projects. To
overcome this, Tuist offers an XcodeProj-based integration that allows you to
integrate Swift Packages in your project using XcodeProj's targets. Thanks to
that, we can not only give you more control over the integration but also make
it compatible with workflows like
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> and
<LocalizedLink href="/guides/features/test/selective-testing">selective test runs</LocalizedLink>.

XcodeProj's integration is more likely to take more time to support new Swift
Package features or handle more package configurations. However, the mapping
logic between Swift Packages and XcodeProj targets is open-source and can be
contributed to by the community. This is contrary to Xcode's default
integration, which is closed-source and maintained by Apple.

To add external dependencies, you'll have to create a `Package.swift` either
under `Tuist/` or at the root of the project.

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
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

::: tip PACKAGE SETTINGS
<!-- -->
The `PackageSettings` instance wrapped in a compiler directive allows you to
configure how packages are integrated. For example, in the example above it's
used to override the default product type used for packages. By default, you
shouldn't need it.
<!-- -->
:::

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS If your project uses custom build
> configurations (configurations other than the standard `Debug` and `Release`),
> you must specify them in the `PackageSettings` using `baseSettings`. External
> dependencies need to know about your project's configurations to build
> correctly. For example:
> 
> ```swift
> #if TUIST
>     import ProjectDescription
> 
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
> 
> See [#8345](https://github.com/tuist/tuist/issues/8345) for more details.

The `Package.swift` file is just an interface to declare external dependencies,
nothing else. That's why you don't define any targets or products in the
package. Once you have the dependencies defined, you can run the following
command to resolve and pull the dependencies into the `Tuist/Dependencies`
directory:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

As you might have noticed, we take an approach similar to
[CocoaPods](https://cocoapods.org)', where the resolution of dependencies is its
own command. This gives control to the users over when they'd like dependencies
to be resolved and updated, and allows opening the Xcode in project and have it
ready to compile. This is an area where we believe the developer experience
provided by Apple's integration with the Swift Package Manager degrades over
time as the project grows.

From your project targets you can then reference those dependencies using the
`TargetDependency.external` dependency type:

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
            bundleId: "dev.tuist.app",
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
<!-- -->
:::

::: info NO SCHEMES GENERATED FOR EXTERNAL PACKAGES
<!-- -->
The **schemes** are not automatically created for Swift Package projects to keep
the schemes list clean. You can create them via Xcode's UI.
<!-- -->
:::

#### Xcode's default integration {#xcodes-default-integration}

If you want to use Xcode's default integration mechanism, you can pass the list
`packages` when instantiating a project:

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

For Swift Macros and Build Tool Plugins, you'll need to use the types `.macro`
and `.plugin` respectively.

::: warning SPM Build Tool Plugins
<!-- -->
SPM build tool plugins must be declared using [Xcode's default
integration](#xcode-s-default-integration) mechanism, even when using Tuist's
[XcodeProj-based integration](#tuist-s-xcodeproj-based-integration) for your
project dependencies.
<!-- -->
:::

A practical application of an SPM build tool plugin is performing code linting
during Xcode's "Run Build Tool Plug-ins" build phase. In a package manifest this
is defined as follows:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

To generate an Xcode project with the build tool plugin intact, you must declare
the package in the project manifest's `packages` array, and then include a
package with type `.plugin` in a target's dependencies.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

Since [Carthage](https://github.com/carthage/carthage) outputs `frameworks` or
`xcframeworks`, you can run `carthage update` to output the dependencies in the
`Carthage/Build` directory and then use the `.framework` or `.xcframework`
target dependency type to declare the dependency in your target. You can wrap
this in a script that you can run before generating the project.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
If you build and test your project through `xcodebuild build` and `tuist test`,
you will similarly need to ensure that the Carthage-resolved dependencies are
present by running the `carthage update` command before building or testing.
<!-- -->
:::

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) expects an Xcode project to integrate the
dependencies. You can use Tuist to generate the project, and then run `pod
install` to integrate the dependencies by creating a workspace that contains
your project and the Pods dependencies. You can wrap this in a script that you
can run before generating the project.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: warning
<!-- -->
CocoaPods dependencies are not compatible with workflows like `build` or `test`
that run `xcodebuild` right after generating the project. They are also
incompatible with binary caching and selective testing since the fingerprinting
logic doesn't account for the Pods dependencies.
<!-- -->
:::

## Static or dynamic {#static-or-dynamic}

Frameworks and libraries can be linked either statically or dynamically, **a
choice that has significant implications for aspects like app size and boot
time**. Despite its importance, this decision is often made without much
consideration.

The **general rule of thumb** is that you want as many things as possible to be
statically linked in release builds to achieve fast boot times, and as many
things as possible to be dynamically linked in debug builds to achieve fast
iteration times.

The challenge with changing between static and dynamic linking in a project
graph is that is not trivial in Xcode because a change has cascading effect on
the entire graph (e.g. libraries can't contain resources, static frameworks
don't need to be embedded). Apple tried to solve the problem with compile time
solutions like Swift Package Manager's automatic decision between static and
dynamic linking, or [Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
However, this adds new dynamic variables to the compilation graph, adding new
sources of non-determinism, and potentially causing some features like Swift
Previews that rely on the compilation graph to become unreliable.

Luckily, Tuist conceptually compresses the complexity associated with changing
between static and dynamic and synthesizes
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</LocalizedLink> that are standard across linking types. In combination
with
<LocalizedLink href="/guides/features/projects/dynamic-configuration">dynamic configurations via environment variables</LocalizedLink>, you can pass the
linking type at invocation time, and use the value in your manifests to set the
product type of your targets.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

Note that Tuist
<LocalizedLink href="/guides/features/projects/cost-of-convenience">does not default to convenience through implicit configuration due to its costs</LocalizedLink>. What this means is that we rely on you setting the
linking type and any additional build settings that are sometimes required, like
the [`-ObjC` linker
flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184),
to ensure the resulting binaries are correct. Therefore, the stance that we take
is providing you with the resources, usually in the shape of documentation, to
make the right decisions.

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
A Swift Package that many projects integrate is [The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture). See
more details in [this section](#the-composable-architecture).
<!-- -->
:::

### Scenarios {#scenarios}

There are some scenarios where setting the linking entirely to static or dynamic
is not feasible or a good idea. The following is a non-exhaustive list of
scenarios where you might need to mix static and dynamic linking:

- **Apps with extensions:** Since apps and their extensions need to share code,
  you might need to make those targets dynamic. Otherwise, you'll end up with
  the same code duplicated in both the app and the extension, causing the binary
  size to increase.
- **Pre-compiled external dependencies:** Sometimes you are provided with
  pre-compiled binaries that are either static or dynamic. Static binaries can
  be wrapped in dynamic frameworks or libraries to be linked dynamically.

When making changes to the graph, Tuist will analyze it and display a warning if
it detects a "static side effect". This warning is meant to help you identify
issues that might arise from linking a target statically that depends
transitively on a static target through dynamic targets. These side effects
often manifest as increased binary size or, in the worst cases, runtime crashes.

## Troubleshooting {#troubleshooting}

### Objective-C Dependencies {#objectivec-dependencies}

When integrating Objective-C dependencies, the inclusion of certain flags on the
consuming target may be necessary to avoid runtime crashes as detailed in [Apple
Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Since the build system and Tuist have no way of inferring whether the flag is
necessary or not, and since the flag comes with potentially undesirable side
effects, Tuist will not automatically apply any of these flags, and because
Swift Package Manager considers `-ObjC` to be included via an `.unsafeFlag` most
packages cannot include it as part of their default linking settings when
required.

Consumers of Objective-C dependencies (or internal Objective-C targets) should
apply `-ObjC` or `-force_load` flags when required by setting `OTHER_LDFLAGS` on
consuming targets.

### Firebase & Other Google Libraries {#firebase-other-google-libraries}

Google's open source libraries — while powerful — can be difficult to integrate
within Tuist as they often use non-standard architecture and techniques in how
they are built.

Here are a few tips that may be necessary to follow to integrate Firebase and
Google's other Apple-platform libraries:

#### Ensure `-ObjC` is added to `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Many of Google's libraries are written in Objective-C. Because of this, any
consuming target will need to include the `-ObjC` tag in its `OTHER_LDFLAGS`
build setting. This can either be set in an `.xcconfig` file or manually
specified in the target's settings within your Tuist manifests. An example:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Refer to the [Objective-C Dependencies](#objective-c-dependencies) section above
for more details.

#### Set the product type for `FBLPromises` to dynamic framework {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Certain Google libraries depend on `FBLPromises`, another of Google's libraries.
You may encounter a crash that mentions `FBLPromises`, looking something like
this:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Explicitly setting the product type of `FBLPromises` to `.framework` in your
`Package.swift` file should fix the issue:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### The Composable Architecture {#the-composable-architecture}

As described
[here](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
and the [troubleshooting section](#troubleshooting), you'll need to set the
`OTHER_LDFLAGS` build setting to `$(inherited) -ObjC` when linking the packages
statically, which is Tuist's default linking type. Alternatively, you can
override the product type for the package to be dynamic. When linking
statically, test and app targets typically work without any issues, but SwiftUI
previews are broken. This can be resolved by linking everything dynamically. In
the example below [Sharing](https://github.com/pointfreeco/swift-sharing) is
also added as a dependency, as it's often used together with The Composable
Architecture and has its own [configuration
pitfalls](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

Following configuration will link everything dynamically - so app + test targets
and SwiftUI previews are working.

::: tip STATIC OR DYNAMIC
<!-- -->
Dynamic linking is not always recommended. See the section [Static or
dynamic](#static-or-dynamic) for more details. In this example, all dependencies
are linked dynamically without conditions for simplicity.
<!-- -->
:::

```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

::: warning
<!-- -->
Instead of `import Sharing` you'll have to `import SwiftSharing` instead.
<!-- -->
:::

### Transitive static dependencies leaking through `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

When a dynamic framework or library depends on static ones through `import
StaticSwiftModule`, the symbols are included in the `.swiftmodule` of the
dynamic framework or library, potentially
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">causing the compilation to fail</LocalizedLink>. To prevent that, you'll have to import
the static dependency using
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</LocalizedLink>:

```swift
internal import StaticModule
```

::: info
<!-- -->
Access level on imports was included in Swift 6. If you're using older versions
of Swift, you need to use
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
instead:
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
