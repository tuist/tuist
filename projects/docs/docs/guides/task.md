---
title: Custom Tuist commands
slug: '/guides/task'
description: 'Learn how to to automate arbitrary tasks with tuist in Swift.'
---

When we write apps, it is often necessary to write some supporting code for e.g. releasing, downloading localizations, etc.
These are often written in Shell or Ruby which only a handful of developers on your team might be familiar with.
This means that these files are edited by an exclusive group and they are sort of "magical" for others.
We try to fix that by introducing a concept of "Tasks" where you can define custom commands - in Swift!

Not only that, we will provide you with an easy integration with tuist, so you can for example inspect your project's graph.

:::warning Alpha
Tasks and the `ProjectAutomation` package are in alpha.
Be aware some APIs might change as we iterate the functionality with the feedback we get from users.
:::

### Defining a task

You can prepend any executable with `tuist-` and add it to your `PATH`. If you for example add `tuist-my-command` to your `PATH`, you will be able to run `tuist my-command` and `tuist-my-command` will automatically be executed.

You can also create a task as a tuist plugin - learn how to do that [here](plugins/creating-plugins.md#Tasks).

## ProjectAutomation

`ProjectAutomation` is a framework for interacting with tuist which can be integrated as Swift package.

Your `Package.swift` for your CLI then may look as the following:
```swift
let package = Package(
    name: "my-cli",
    products: [
        .executable(name: "my-cli", targets: ["my-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/ProjectAutomation", .upToNextMajor(from: "x.y.z")), // Add ProjectAutomation as a package
    ],
    targets: [
        .target(
            name: "my-cli",
            dependencies: [
                .product(name: "ProjectAutomation", package: "ProjectAutomation") // Integrate ProjectAutomation framework
            ]
        ),
    ]
)
```

### Graph

To get your project's graph, you can leverage `Tuist`'s `graph` method. Here is an example how you might use this method:

```swift
import ProjectAutomation

let graph = try Tuist.graph()

let targets = graph.projects.values.flatMap(\.targets)
print("These are the current project's targets: \(targets))"
```

You might wonder what the return value of `Tuist.graph()` is - the method returns a Swift model `Graph`. Below you will find the exact specification.

#### Graph

| Property       | Description                                                   | Type    |
| ---------- | ------------------------------------------------------------- | ------- |
| `name`| Name of the graph | `String` |
| `path` | Absolute path of the graph | `String` |
| `projects` | Projects which are a part of the graph | `[String: Project]` |

#### Project

| Property       | Description                                                   | Type    |
| ---------- | ------------------------------------------------------------- | ------- |
| `name`| Name of the project | `String` |
| `path` | Absolute path of the project | `String` |
| `isExternal` | Indicates whether the project is imported through `Dependencies.swift` | `Bool` |
| `packages` | Swift packages that this project depends on | `[Package]` |
| `targets` | Targets of this projects | `[Target]` |
| `schemes` | Defined schemes for this project | `[Scheme]` |

#### Target

| Property       | Description                                                   | Type    |
| ---------- | ------------------------------------------------------------- | ------- |
| `name`| Name of the target | `String` |
| `product` | Product type the target produces | `String` |
| `sources` | List of file paths that are the target's sources. | `[String]` |

#### Package

| Property       | Description                                                   | Type    |
| ---------- | ------------------------------------------------------------- | ------- |
| `kind`| The type of the package | `PackageKind` |
| `path` | The path of the package. For a local package, the path is an absolute path to the package directory. For a remote package, it it value of the URL of the package. | `String` |

#### PackageKind

| Case       | Description                                                   |
| ---------- | ------------------------------------------------------------- |
| `remote` | Represents a remote package
| `local` | Represents a local package |


#### Scheme

| Property       | Description                                                   | Type    |
| ---------- | ------------------------------------------------------------- | ------- |
| `name` | Name of the scheme | `String` |
| `testActionTargets` | Targets which can be tested via this scheme | `[String]?`
