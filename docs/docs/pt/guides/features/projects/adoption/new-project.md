---
title: Create a new project
titleTemplate: :title · Adoption · Projects · Develop · Guides · Tuist
description: Learn how to create a new project with Tuist.
---

# Create a new project {#create-a-new-project}

The most straightforward way to start a new project with Tuist is to use the `tuist init` command. This command launches an interactive CLI that guides you through setting up your project. When prompted, make sure to select the option to create a "generated project".

One of the files that are generated is the `Project.swift`, which contains the definition of your project. If you are familiar with the Swift Package Manager, think of it as the `Package.swift` but with the lingo of Xcode projects. You can then <LocalizedLink href="/guides/features/projects/editing">edit the project</LocalizedLink> running `tuist edit`, and Xcode will open a project where you can edit the project.

::: code-group

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```

:::

> [!NOTE]
> We intentionally keep the list of available templates short to minimize maintenance overhead. If you want to create a project that doesn't represent an application, for example a framework, you can use `tuist init` as a starting point and then modify the generated project to suit your needs.

## Manually creating a project {#manually-creating-a-project}

Alternatively, you can create the project manually. We recommend doing this only if you're already familiar with Tuist and its concepts. The first thing that you'll need to do is to create additional directories for the project structure:

```bash
mkdir MyFramework
cd MyFramework
```

Then create a `Tuist.swift` file, which will configure Tuist and is used by Tuist to determine the root directory of the project, and a `Project.swift`, where your project will be declared:

::: code-group

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "io.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```

```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

:::

> [!IMPORTANT]
> Tuist uses the `Tuist/` directory to determine the root of your project, and from there it looks for other manifest files globbing the directories. We recommend creating those files with your editor of choice, and from that point on, you can use `tuist edit` to edit the project with Xcode.
