---
title: Sharing code across manifests
slug: '/guides/helpers'
description: Project description helpers are a group of Swift files that can be accessed from any project manifest. They are useful to extract common patterns, define project conventions, or simplify the definition of projects.
---

One of the inconveniences of Xcode when we use it with large projects is that it doesn't allow reusing elements of the projects other than the build settings through `.xcconfig` files. Being able to reuse project definitions is useful for the following reasons:

- It eases the **maintenance** because changes can be applied in one place and all the projects get the changes automatically.
- It makes it possible to define **conventions** that new projects can conform to.
- Projects are more **consistent** and therefore the likelihood of broken builds due inconsistencies is significantly less.
- Adding a new projects becomes an easy task because we can reuse the existing logic.

Reusing code across manifest files is possible in Tuist thanks to the concept of **project description helpers**.

### Definition

Project description helpers are Swift files that get compiled into a framework, `ProjectDescriptionHelpers`, that manifest files can import.

:::note Structure
Tuist is not opinionated about the files structure and the content in them so it's up to you to give them a structure that makes sense for your project.
:::

You can import them into your manifest file by adding an import statement at the top of the file:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

### Location

Tuist traverses up the directory hierarchy until it finds a `Tuist` directory. Then it builds the helpers module including all the files under the `ProjectDescriptionHelpers` directory in the `Tuist` directory.

### Example

The snippets below contain an example of how we extend the `Project` model to add static constructors and how we use them from a `Project.swift` file:

**Project+Templates.swift**

```swift
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            Target(
                name: name,
                platform: .iOS,
                product: .framework,
                bundleId: "io.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            Target(
                name: "\(name)Tests",
                platform: .iOS,
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

**Project.swift**

```swift {2}
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```

:::note Conventions
Note how through the function we are defining conventions about the name of the targets, the bundle identifier, and the folders structure.
:::
