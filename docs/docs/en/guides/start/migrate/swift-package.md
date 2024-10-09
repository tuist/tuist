---
title: Migrate a Swift Package
description: Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects.
---

# Migrate a Swift Package

Swift Package Manager emerged as a dependency manager for Swift code that uninentionally found itself solving the problem of managing projects and supporting other programming languages like Objective-C. Because the tool was designed with a different purpose in mind, it can be challenging to use it to manage projects at scale because it lacks flexibility, performance, and power that Tuist provides. This is well captured in the [Scaling iOS at Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) article, which includes the following table comparing the performance of Swift Package Manager and native Xcode projects:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="./images/performance-table.webp">

We often come across developers and organizations that challenge the need for Tuist considering that Swift Package Manager can take a similar project management role. Some venture into a migration to later on realize that their developer experience has degraded signicantly. For instance, the rename of a file might take up to 15 seconds to re-index. 15 seconds!

**Whether Apple will make Swift Package Manager a built-for-scale project manager is uncertain.** However, we are not seeing any signs that it's happening. In fact, we are seeing quite the opposite. They are making Xcode-inspired decisions, like achieving convenience through implicit configurations, which [as you might know,](/guides/develop/projects/cost-of-convenience) is the source of complications at scale. We believe it'd take Apple to go to first principles and revisit some decisions that made sense as a dependency manager but not as a project manager, for example the usage of a compiled language as an interface to define projects.

> [!TIP] SPM AS JUST A DEPENDENCY MANAGER
> Tuist treats Swift Package Manager as a dependency manager, and it's a great one. We use it to resolve dependencies and to build them. We don't use it to define projects because it's not designed for that.

## Migrating from Swift Package Manager to Tuist

The similarities between Swift Package Manager and Tuist make the migration process straightforward. The main difference is that you'll be defining your projects using Tuist's DSL instead of `Package.swift`.

First, create a `Project.swift` file next to your `Package.swift` file. The `Project.swift` file will contain the definition of your project. Here's an example of a `Project.swift` file that defines a project with a single target:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

Some things to note:

- **ProjectDescription**: Instead of using `PackageDescription`, you'll be using `ProjectDescription`.
- **Project:** Instead of exporting a `package` instance, you'll be exporting a `project` instance.
- **Xcode language:** The primitives that you use to define your project mimic Xcode's language, so you'll find schemes, targets, and build phases among others.

Then create a `Tuist/Config.swift` file with the following content:

```swift
import ProjectDescription

let config = Config()
```

The `Config.swift` contains the configuration for your project and its directory, `Tuist`, serves as a reference to determine the root of your project. You can check out the [directory structure](/guides/develop/projects/directory-structure) document to learn more about the structure of Tuist projects.

## Editing the project

You can use [`tuist edit`](/guides/develop/projects/editing) to edit the project in Xcode. The command will generate an Xcode project that you can open and start working on.

```bash
tuist edit
```

Depending on the size of the project, you might consider using it in one shot or incrementally. We recommend starting with a small project to get familiar with the DSL and the workflow. Our advise is always to start from the most depended upon target and work all the way up to the top-level target.