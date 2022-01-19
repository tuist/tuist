---
title: Defining dependencies
slug: '/guides/dependencies'
description: Defining dependencies between modules is a straightforward task in Tuist. This document describes how to use this feature, and all types of dependencies that targets can define.
---

**Setting up dependencies in Xcode projects isn't straightforward**. When dependencies have transitive dependencies things get complicated because it requires changes in the targets that are part of the branch where the transitive dependency is. To illustrate that, think about an app, depending on a dynamic framework `Search`, which has no dependencies. If at some point in the future we add a new dynamic framework `Core`, on which `Search` depends, we'll need to update not only `Search`, but the app to embed the framework into the product.

Imagine a modular app made of 8 projects, with at least two targets in each of them \(to compile the framework/library and run the tests\), with dependencies between them. That's a very common setup in large projects, especially if you need to reuse code across different targets. With 16 targets to set up, **there's much knowledge that the developers need to keep in mind to do things the right way**. Who is depending on this target? Where do I need to embed this dynamic framework? Which build settings should I update to make the public interface of the library available?

Fortunately, **Tuist takes care of all that work for you**. It allows you to define dependencies and it uses that knowledge to set up the targets with the right build phases and build settings.
If you noticed when we first introduced the manifest file, there isn't any public model for defining linking build phases. We made that on purpose because **we'd like to figure out all those things for you**.

### Defining dependencies

The `Target` model that we use from the manifest has a property, `dependencies`, that allows you to define the dependencies of the target.

```swift
let target = Target(
    dependencies: [

    ]
    /* Rest of the manifest*/
)
```

A dependency can be any of the following types.

### Target dependencies

```swift
.target("App")
```

It defines a dependency with another target in the same project. For instance, a tests target depends on the target that is being tested.

:::note Tests host app
In order for an app to be the host target of a tests target, the app target should be added as a dependency.
:::

### Target dependencies across projects

```swift
.project(target: "Core", path: "../Core")
```

It defines a dependency with a target in another project. When the workspace gets generated, the other project is also included so that Xcode knows how to compile that other target.

### Framework dependencies

```swift
.framework(path: "Carthage/Build/iOS/Alamofire.framework")
```

It defines a dependency with a pre-compiled framework, for example, a framework that has been compiled by Carthage. If the framework contains multiple architectures, Tuist will add an extra build phase to strip them.

### Library dependencies

```swift
.library(
    path: "Vendor/Library.a",
    publicHeaders: nil,
    swiftModuleMap: "Vendor/Library.modulemap"
)
```

It defines a dependency with a pre-compiled library. It allows specifying the path where the public headers or Swift module map is.

### System libraries and frameworks dependencies

```swift
.sdk(name: "StoreKit.framework", status: .required)
```

```swift
.sdk(name: "ARKit.framework", status: .optional)
```

```swift
.sdk(name: "libc++.tbd")
```

It defines a dependency on a system library (`.tbd`) or framework (`.framework`) and optionally if it is `required` or `optional` (i.e. gets weakly linked).

### XCTest dependencies

It's used to indicate a dependency with the system's `XCTest` framework. Unlike SDK dependencies, `XCTest.framework` is located under the directory `$(PLATFORM_DIR)/Developer/Library/Frameworks` and requires Tuist to expose that path through the `FRAMEWORK_SEARCH_PATH` build setting.

You can read more about the different locations of frameworks on [this issue](https://github.com/tuist/tuist/issues/837).

```swift
.xctest
```

### SPM dependencies

Targets can add Swift package products as dependencies:

```swift
.package(product: "LibraryA")
```

### CocoaPods dependencies

Targets can indicate that they have [CocoaPods](https://cocoapods.org) dependencies defined in a `Podfile`:

```swift
.cocoapods(path: ".") // Expects a Podfile in the directory of the target's project
```

Tuist looks up CocoaPods using Bundler. If it's not defined, it falls back to the system's CocoaPods. If CocoaPods can't be found in the environment, the installation of the dependencies will fail.

:::note Repository update
The underlying 'pod install' is executed with the `--update-repo` argument to ensure the local repository of pod specs is up to date.
:::

:::note Podfile validation
Tuist does not parse the CocoaPods dependency graph nor runs any validation. It's the user responsibility ensure the right format of the 'Podfile'.
:::

### XCFramework dependencies

```swift
.xcframework(path: "Frameworks/Alamofire.xcframework")
```

It defines a dependency with a pre-compiled xcframework.

### External dependencies

```swift
.external(name: "Alamofire")
```

It defines a dependency from an external dependency defined in the `Dependencies.swift` file.

For more information, have a look at the [dedicated section](guides/third-party-dependencies.md).
