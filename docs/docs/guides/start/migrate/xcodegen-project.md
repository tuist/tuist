---
title: Migrate an XcodeGen project
description: Learn how to migrate your projects from XcodeGen to Tuist.
---

# Migrate an XcodeGen project

[XcodeGen](https://github.com/yonaskolb/XcodeGen) is a project-generation tool that uses YAML as [a configuration format](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) to define Xcode projects. Many organizations **adopted it trying to escape from the frequent Git conflicts that arise when working with Xcode projects.** However, frequent Git conflicts is just one of the many problems that organizations experience. Xcode exposes developers with a lot of intricacies and implicit configurations that make it hard to maintain and optimize projects at scale. XcodeGen falls short there by design because it's a tool that generates Xcode projects, not a project manager. If you need a tool that helps you beyond generating Xcode projects, you might want to consider Tuist.

> [!TIP] SWIFT OVER YAML
> Many organizations prefer Tuist as a project generation tool too because it uses Swift as a configuration format. Swift is a programming language that developers are familiar with, and that provides them with the convenience of using Xcode's autocompletion, type-checking, and validation features. 

What follows are some considerations and guidelines to help you migrate your projects from XcodeGen to Tuist.

## Project generation

Both Tuist and XcodeGen provide a `generate` command that turns your project declaration into Xcode projects and workspaces.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
:::

The difference lays in the editing experience. With Tuist, you can run the `tuist edit` command, which generates an Xcode project on the fly that you can open and start working on. This is particularly useful when you want to make quick changes to your project.

## `project.yaml`

XcodeGen's `project.yaml` description file becomes `Project.swift`. Moreover, you can have `Workspace.swift` as a way to customize how projects are grouped in workspaces. You can also have a project `Project.swift` with targets that reference targets from other projects. In those cases, Tuist will generate an Xcode Workspace including all the projects.

::: code-group

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist/
    Config.swift
  Project.swift
  Workspace.swift
```
:::

> [!TIP] XCODE'S LANGUAGE
> Both XcodeGen and Tuist embrace Xcode's language and concepts. However, Tuist's Swift-based configuration provides you with the convenience of using Xcode's autocompletion, type-checking, and validation features.

## Spec templates

One of the disadvantages of YAML as a language for project configuration is that it doesn't support reusability across YAML files out of the box. This is a common need when describing projects, which XcodeGen had to solve with their own propietary solution named *"templates"*. With Tuist's re-usability is built into the language itself, Swift, and through a Swift module named [project description helpers](/guides/develop/projects/code-sharing), which allow reusing code across all your manifest files.

::: code-group
```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```
```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```