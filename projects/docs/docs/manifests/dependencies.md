---
title: Dependencies.swift
slug: '/manifests/dependencies'
description: This page documents how the Dependencies.swift manifest file can be used define the contract between the dependency managers and Tuist.
---

:::warning Work in progress
This feature is currently being worked on and is not ready to be used yet.
:::

Learn how to get started with `Dependencies.swift` [here](/guides/third-party-dependencies/).

```swift
import ProjectDescription

let dependencies = Dependencies(
    carthage: .carthage(
        [
            .github(path: "Alamofire/Alamofire", requirement: .exact("5.0.4"))
        ],
        options: [.useXCFrameworks, .noUseBinaries]
    ),
    swiftPackageManager: nil, // work in progress, pass `nil`
    platforms: [.iOS]
)
```

### Dependencies

A `Dependencies` manifest allows for defining external dependencies for Tuist.

| Property              | Description                                                                        | Type                                                                     | Required | Default                  |
| --------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | -------- | ------------------------ |
| `carthage`            | The description of a dependency that can be installed using Carthage.              | [`CarthageDependencies`](#carthage-dependencies)                         | No       | `nil`                    |
| `swiftPackageManager` | The description of a dependency that can be installed using Swift Package Manager. | [`SwiftPackageManagerDependencies`](#swift-package-manager-dependencies) | No       | `nil`                    |
| `platforms`           | List of platforms for which you want to install depedencies.                       | [`Set<Platform>`](/manifests/project#platform)                           | No       | `Set(Platform.allCases)` |

### Carthage Dependencies

Contains the description of a dependency that can be installed using Carthage.

| Property       | Description                                                | Type                                                                     | Required | Default |
| -------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------ | -------- | ------- |
| `dependencies` | List of depedencies that will be installed using Carthage. | [`[CarthageDependencies.Dependency]`](#carthage-dependencies-dependency) | Yes      |         |
| `options`      | List of options for Carthage installation.                 | [`Set<CarthageDependencies.Options>`](#carthage-dependencies-options)    | No       | `[]`    |

### Carthage Dependencies Dependency

Specifies origin of Carthage dependency.

| Case                           | Description                                                            |
| ------------------------------ | ---------------------------------------------------------------------- |
| `.github(String, Requirement)` | GitHub repositories (both GitHub.com and GitHub Enterprise).           |
| `.git(String, Requirement)`    | Other Git repositories.                                                |
| `.binary(String, Requirement)` | Dependencies that are only available as compiled binary `.framework`s. |

### Carthage Dependencies Options

The options that you can set for Carthage installation.

| Case               | Description                                                                                                                                                                             |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.useXCFrameworks` | When passed, Carthage will produce XCFrameworks instead of regular frameworks. Refers to `--use-xcframeworks` Carthage flag. **Note: It requires Carthage in version at least 0.37.0.** |
| `.noUseBinaries`   | When passed, Carthage will rebuild dependencies from source instead of using downloaded binaries when possible. Refers to `--no-use-binaries` Carthage flag.                            |

### SwiftPackageManagerDependencies

Contains the description of a dependency that can be installed using Swift Package Manager.

| Property   | Description                                                          | Type                                      | Required | Default |
| ---------- | -------------------------------------------------------------------- | ----------------------------------------- | -------- | ------- |
| `packages` | List of packages that will be installed using Swift Package Manager. | [`[Package]`](/manifests/project#package) | Yes      |         |
