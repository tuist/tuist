---
title: Dependencies.swift
slug: '/manifests/dependencies'
description: This page documents how the Dependencies.swift manifest file can be used define the contract between the dependency managers and Tuist.
---

Learn how to get started with `Dependencies.swift` [here](guides/third-party-dependencies.md).

```swift
import ProjectDescription

let dependencies = Dependencies(
    carthage: [
        .github(path: "Alamofire/Alamofire", requirement: .exact("5.0.4")),
    ],
    swiftPackageManager: [
        .remote(url: "https://github.com/Alamofire/Alamofire", requirement: .upToNextMajor(from: "5.0.0")),
    ],
    platforms: [.iOS]
)
```

### Dependencies

A `Dependencies` manifest allows for defining external dependencies for Tuist.

| Property              | Description                                                                        | Type                                                                     | Required | Default                  |
| --------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | -------- | ------------------------ |
| `carthage`            | The description of a dependency that can be installed using Carthage.              | [`CarthageDependencies`](#carthage-dependencies)                         | No       | `nil`                    |
| `swiftPackageManager` | The description of a dependency that can be installed using Swift Package Manager. | [`SwiftPackageManagerDependencies`](#swift-package-manager-dependencies) | No       | `nil`                    |
| `platforms`           | List of platforms for which you want to install dependencies.                       | [`Set<Platform>`](manifests/project.md#platform)                           | No       | `Set(Platform.allCases)` |

### CarthageDependencies

Contains the description of a dependency that can be installed using Carthage.

| Property       | Description                                                | Type                                                                     | Required | Default |
| -------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------ | -------- | ------- |
| `dependencies` | List of dependencies that will be installed using Carthage. | [`[CarthageDependencies.Dependency]`](#carthage-dependencies-dependency) | Yes      |         |

### CarthageDependencies Dependency

Specifies origin of Carthage dependency.

| Case                           | Description                                                            |
| ------------------------------ | ---------------------------------------------------------------------- | --- |
| `.github(String, Requirement)` | GitHub repositories (both GitHub.com and GitHub Enterprise).           |
| `.git(String, Requirement)`    | Other Git repositories.                                                |
| `.binary(String, Requirement)` | Dependencies that are only available as compiled binary `.framework`s. |     |

### SwiftPackageManagerDependencies

Contains the description of a dependency that can be installed using Swift Package Manager.

| Property   | Description                                                          | Type                                      | Required | Default |
| ---------- | -------------------------------------------------------------------- | ----------------------------------------- | -------- | ------- |
| `packages` | List of packages that will be installed using Swift Package Manager. | [`[Package]`](manifests/project.md#package) | Yes      |         |
| `productTypes` | Mapping from SPM targets to custom Tuist product types. If not specified, the SPM defined product is used, or `staticFramwork` if the SPM product is automatic. | [`[String: Product]`](manifests/project.md#product) | Yes      |         |
