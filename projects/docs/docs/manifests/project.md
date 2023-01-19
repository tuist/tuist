---
title: Project.swift
description: 'This page documents the models that users can use to define their project: how to initialize them, attributes and their meaning, protocol conformances.'
slug: '/manifests/project'
---

Projects are defined in `Project.swift` files, which we refer to as manifest files. The snippet below shows an example project manifest:

```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["Sources/**"]
        )
    ]
)
```

### API documentation

The API documentation for the latest version and main branch is available here:

* [latest](https://tuist.github.io/tuist/latest/documentation/projectdescription/project)
* [main](https://tuist.github.io/tuist/main/documentation/projectdescription/project)

Other versions can be found at https://tuist.github.io/tuist/VERSION/documentation/projectdescription/project by replacing `VERSION` with a version number (like X.Y.Z)