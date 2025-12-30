---
title: "Faster Vapor clean builds with Tuist"
category: "learn"
tags: ["Swift", "Vapor", "Server"]
excerpt: "Discover how to boost productivity in server-side Swift development using Vapor with Tuist. Manage dependencies efficiently and optimize build times for better workflow."
author: pepicrft
---

If you build **server-side apps** with Swift, you likely use the [Vapor](https://vapor.codes) framework. For those unfamiliar, Vapor is an excellent framework for building server-side Swift applications. It's built atop [SwiftNIO](https://github.com/apple/swift-nio) and boasts impressive performance. Vapor projects and their dependencies are managed using the [Swift Package Manager](https://www.swift.org/package-manager/). You can open `Package.swift` in Xcode to run your project, or alternatively, use other IDEs like [VSCode](https://code.visualstudio.com), which offers robust support for Swift projects through [extensions](https://marketplace.visualstudio.com/items?itemName=sswg.swift-lang) and is available on various operating systems.

When I first tried Vapor, having previously worked with [Ruby](https://www.ruby-lang.org) and [JavaScript](https://en.wikipedia.org/wiki/JavaScript), where code is almost instantly hot-reloaded, I was surprised to find that a newly created project took a long time to compile. Swift Package Manager and Xcode can build incrementally after the first build, but clean builds, which are slow, occur more often than desired. This happens in continuous integration (CI) and when developers clear their derived data directory to resolve Xcode issues. This issue isn't specific to Vapor but affects any Swift Package or Xcode project. It's one of the reasons we started using Tuist to manage the Tuist project, relegating Swift Package Manager to dependency management only. I was curious to see if Tuist could be used with Vapor projects, and the answer was yes. I'd like to share how you can do the same.

## A Tuist-Managed Vapor Project

If you're familiar with describing a package in `Package.swift`, using Tuist will feel similar. In this case, you describe your project in a `Project.swift` file:

```swift
import ProjectDescription

let project = Project(name: "Hello",
                      targets: [
                        Target(name: "App",
                               platform: .macOS,
                               product: .commandLineTool,
                               bundleId: "io.tuist.Vapor",
                               sources: ["Sources/App/**/*.swift"],
                               dependencies: [.external(name: "Vapor")])
                      ])
```

Note that the target is a `commandLineTool`. Xcode will generate an executable that you can run from the command line. Also, it declares an external dependency on the `Vapor` product.

Tuist provides an alternative solution for managing dependencies, building upon Swift Package Manager. Packages are declared in a `Tuist/Dependencies.swift` or `Tuist/Package.swift` file, and Tuist uses Swift Package Manager to fetch them. When integrated into your projects, they are converted into standard Xcode projects and targets, giving you more control over the integration and allowing us to optimize and validate the graph.

Create a `Tuist/Dependencies.swift` file like this:


```swift
import ProjectDescription

let dependencies = Dependencies(swiftPackageManager: .init([
    .remote(url: "https://github.com/vapor/vapor.git", requirement: .upToNextMinor(from: "4.83.1"))
], productTypes: [
    "Atomics": .framework
]), platforms: Set(arrayLiteral: .macOS))
```

> We are deprecating `Tuist/Dependencies.swift` in favor of `Tuist/Package.swift` for better compatibility with dependency updating tools. While we already support it, we recommend using the current interface until both provide a comparable developer experience.

Changing the product type of `Atomics` to a dynamic framework is crucial; otherwise, the application will fail at runtime.

Once you have the `Project.swift` and `Tuist/Dependencies.swift` files, run `tusit fetch` to fetch the dependencies, and `tuist generate` to create and open an Xcode project from where you can run your app.

## Binary Caching

Until now, everything mentioned is achievable with Swift Package Manager. Suppose you want to avoid compiling dependencies on every clean build. In that case, `tuist cache warm` turns every project target into binaries using a fingerprinting mechanism. After running this command, Tuist will compile every target in the graph.

Once complete, run `tuist generate`. By default, it will use the cached binaries for dependencies. Since your project has a single target, that should be the only one with sources.

## Modular Architecture

Binary caching also applies to your targets, but it requires a modular architecture to be effective. We recommend splitting your target into smaller ones so that targets depend on other targets' interfaces, avoiding a single target with numerous dependencies. Both Swift Package Manager and Tuist make maintaining a project with many targets easier, so don't hesitate to have multiple targets. Then, invoke Tuist, specifying the targets you want to focus on:

```bash
tuist generate Settings Documentation
```

Tuist will include the sources of these targets and attempt to use binaries for everything else, including your project targets.

If you wish to share binaries across environments, use [Tuist Cache](https://docs.tuist.dev/en/guides/develop/cache). Sign in with `tuist auth login` and create your projects. Your CI times, and consequently costs, will significantly reduce, sometimes by up to 80%.

## Linux

Tuist works with Xcode projects, targeting Apple platforms. However, you'll likely want to run your Vapor app on Linux. Therefore, we recommend maintaining a CI pipeline that ensures your app and tests compile and run on Linux. To keep CI times low on pull requests (PRs), consider setting up the pipeline to run on `main`, automatically reverting PRs if regressions are detected.

## Conclusion

The productivity gains from using Tuist extend beyond Vapor apps to any Swift Package or Xcode project. Many organizations don't realize the cost of slow builds until they start using Tuist. Others switch from Swift to other languages or ecosystems with better build times. Our goal is to change this by simplifying the adoption and use of these improvements. Check out [this project](https://github.com/tuist/tuist-vapor-example) to see the concepts discussed here in action.
