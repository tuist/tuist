---
title: Dependencies.swift
slug: '/manifests/dependencies'
description: This page documents how the Dependencies.swift manifest file can be used to define the contract between the dependency managers and Tuist.
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

### API documentation

The API documentation for the latest version and main branch is available here:

* [latest](https://tuist.github.io/tuist/latest/documentation/projectdescription/dependencies)
* [main](https://tuist.github.io/tuist/main/documentation/projectdescription/dependencies)

Other versions can be found at https://tuist.github.io/tuist/VERSION/documentation/projectdescription/dependencies by replacing `VERSION` with a version number (like X.Y.Z)
