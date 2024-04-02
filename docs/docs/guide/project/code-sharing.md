---
title: Code sharing
description: Learn how to share code across manifest files to reduce duplications and ensure consistency
---

# Code sharing

One of the inconveniences of Xcode when we use it with large projects is that it doesn't allow reusing elements of the projects other than the build settings through `.xcconfig` files. Being able to reuse project definitions is useful for the following reasons:

- It eases the **maintenance** because changes can be applied in one place and all the projects get the changes automatically.
- It makes it possible to define **conventions** that new projects can conform to.
- Projects are more **consistent** and therefore the likelihood of broken builds due inconsistencies is significantly less.
- Adding a new projects becomes an easy task because we can reuse the existing logic.

Reusing code across manifest files is possible in Tuist thanks to the concept of **project description helpers**.

> [!TIP] A TUIST UNIQUE ASSET
> Many organizations like Tuist because they see in project description helpers a platform for platform teams to codify their own conventions and come up with their own language for describing their projects. For example, YAML-based project generators have to come up with their own YAML-based propietary templating solution, or force organizations onto building their tools upon.

## Project description helpers

Project description helpers are Swift files that get compiled into a module, `ProjectDescriptionHelpers`, that manifest files can import. The module is compiled by gathering all the files in the `Tuist/ProjectDescriptionHelpers` directory.

You can import them into your manifest file by adding an import statement at the top of the file:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` are available in the following manifests:
- `Project.swift`
- `Package.swift` (only behind the `#TUIST` compiler flag)
- `Workspace.swift`

## Example

The snippets below contain an example of how we extend the `Project` model to add static constructors and how we use them from a `Project.swift` file:

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "io.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "io.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
:::

> [!TIP] A TOOL TO ESTABLISH CONVENTIONS
> Note how through the function we are defining conventions about the name of the targets, the bundle identifier, and the folders structure.
