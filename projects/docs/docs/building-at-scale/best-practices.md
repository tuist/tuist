---
title: Best practices
slug: '/building-at-scale/best-practices'
description: Xcode being weakly opinionated in regards to the project structure might result in complex and hard to manage project. To prevent that, this document describes best practices that users of Tuist can follow to have projects that are optimal and easy to reason about.
---

Although Tuist defaults to some conventions on the projects that are initialized with Tuist, its API doesn't enforce them purposedly to ease the adoption of the tool. Very often, Xcode projects end up being complex because Xcode is weakly opinionated about the project structure. As long as the build system is able to process build settings and phases and output valid, it's all good.

**Complex and non-conventional projects** are undesirable because they are hard to reason about and might lead to compilation errors. The result of that is that only a few people in the team can make well-informed decisions to scale up the project. In other words, your team ends up with a high [bus factor](https://en.wikipedia.org/wiki/Bus_factor).

The good news is that Tuist is an excellent tool to **codify conventions**: _how files are structured in frameworks, how frameworks should be named,
how resources should be bundled._ Although they are not necessary to benefit from Tuist, we encourage spending some time defining them for your project and codifying them in your project manifests.

This document contains a list of recommendations for conventions that we'd follow to **ease scaling up** your projects.

### Dependencies

- **Explicit definition:** Dependencies can be defined implicitly through build settings. Xcode is smart enough to detect them and determine the order in which targets should be built. Although implicitness might work fine in small projects, as they get larger, it might turn into a source of issues and slowness. Default to explicit definition of dependencies using the [dependencies API](guides/dependencies.md) that Tuist provides. Tuist has handy built-in features such as [tuist graph](commands/graph.md) or detection of circular dependencies that rely on dependencies being explicitly defined.
- **XCTest dependency:** If a target that is not a test target depends on `XCTest`, declare the dependency explicitly with `.xctest`.
- **Avoid re-exported modules:** If a target A, re-exports a dependency B using the syntax `@_exported`, to a target C, B should be a dependency of C. Dependencies defined through [re-exports](https://github.com/apple/swift/blob/main/docs/Modules.rst#modules-can-re-export-other-modules) create implicit dependencies that complicate [caching](building-at-scale/caching.md). If that setup is not possible because it leads to duplicated symbols, you might consider wrapping the transitive static dependency into a dynamic target.

### File structure

- **Keep it simple:** Although the API for defining a list of files is very flexible, we discourage having a complex file structure because they increase the project generation time and make it hard for developers to spot at glance what belongs to what. A complex file structure is a structure where files of different nature are placed alongside and require the usage of glob patterns and excluded files that are expensive to resolve.

```swift
// Recommended
let target = Target(name: "MyFramework", sources: ["MyFramework/Sources"])

// Discouraged
let target = Target(name: "MyFramework", sources: ["MyFramework/**/*.swift"])
```
