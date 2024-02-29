# Workspace

You can customize your generated workspace in the `Workspace.swift` file.

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
