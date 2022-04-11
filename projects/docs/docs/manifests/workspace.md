---
title: Workspace.swift
slug: '/manifests/workspace'
description: 'This page documents how the Workspace.swift manifest file can be used to group projects together, add additional files, and define workspace schemes.'
---

By default, `tuist generate` generates an Xcode workspace that has the same name as the current project. It includes the project and all its dependencies. Tuist allows customizing this behaviour by defining a workspace manifest within a `Workspace.swift` file. Workspace manifests allow specifying a list of projects to generate and include in an Xcode workspace. Those projects don’t necessarily have to depend on one another. Additionally, files and folder references _(such as documentation files)_ can be included in a workspace manifest.

The snippet below shows an example workspace manifest:

```swift
import ProjectDescription

let workspace = Workspace(
    name: "CustomWorkspace",
    projects: [
        "App",
        "Modules/**"
    ]
)
```

Although `Workspace.swift` file can reside in any directory (including a project directory), we recommend defining it at the root of the project.

### API documentation

The API documentation for the latest version and main branch is available here:

* [latest](https://tuist.github.io/tuist/latest/documentation/projectdescription/workspace)
* [main](https://tuist.github.io/tuist/main/documentation/projectdescription/workspace)

Other versions can be found at https://tuist.github.io/tuist/VERSION/documentation/projectdescription/workspace by replacing `VERSION` with a version number (like X.Y.Z)
