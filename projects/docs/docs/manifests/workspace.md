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
    ],
    schemes: [
        Scheme(
            name: "Workspace-App",
            shared: true,
            buildAction: .buildAction(
                targets: [.project(path: "App", target: "App")],
                preActions: []
            ),
            testAction: .targets(
                [TestableTarget(target: .project(path: "App", target: "AppTests"))]
            ),
            runAction: .runAction(
                executable: .project(path: "App", target: "App")
            ),
            archiveAction: .archiveAction(
                configuration: "Debug",
                customArchiveName: "Something2"
            )
        )
    ],
    additionalFiles: [
        "Documentation/**",
        .folderReference(path: "Website")
    ],
    generationOptions: [
        .automaticSchemaGeneration(.disabled)
    ]
)
```

Although `Workspace.swift` file can reside in any directory (including a project directory), we recommend defining it at the root of the project:

## Workspace

A `Workspace.swift` should initialize a variable of type `Workspace`. It can take any name, although we recommend to stick to `workspace`. A workspace accepts the following attributes:

| Property             | Description                                                                                                       | Type                                                              | Required | Default   |
| -------------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------- | --------- |
| `name`               | Name of the workspace. It’s used to determine the name of the generated Xcode workspace.                          | `String`                                                          | Yes      |           |
| `projects`           | List of paths (or glob patterns) to projects to generate and include within the generated Xcode workspace.        | [`[Path]`](manifests/project.md#path)                             | Yes      |           |
| `schemes`            | List of custom schemes to include in the workspace                                                                | [`[Scheme]`](manifests/project.md#scheme)                         | No       |           |
| `fileHeaderTemplate` | Lets you define custom file header template macro for built-in Xcode file templates.                              | [`FileHeaderTemplate`](manifests/project.md#file-header-template) | No       |           |
| `additionalFiles`    | List of files to include in the workspace - these won't be included in any of the projects or their build phases. | [`[FileElement]`](manifests/project.md#fileelement)               | No       | `[]`      |
| `generationOptions`  | Options to configure the generation of the Xcode workspace.                                                       | [`Workspace.GenerationOptions`](#generationoptions)               | No       | See below |

## GenerationOptions

Generation options allow customizing the generation of the Xcode workspace.

| Property                                                | Description                                                                                                                                                              | Type                                                              | Required | Default                                                     |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- | -------- | ----------------------------------------------------------- |
| `disableAutomaticXcodeSchemes`                          | Enable or disable automatic generation of schemes _by Xcode_.                                                                                                            | [`AutomaticSchemeMode`](#automaticschememode)                     | No       | `false`                                                     |
| `autogeneratedWorkspaceSchemes(AutogenerationOptions)` | Enable or disable automatic generation of `*-Workspace*` schemes. If enabled, options to configure code coverage and test targets can be passed in via associated values. | [`AutogeneratedWorkspaceSchemes`](#autogeneratedworkspaceschemes) | No       | `.enabled(codeCoverageMode: .disabled, testingOptions: [])` |

### CodeCoverageMode

Allows you to define what targets will be enabled for code coverage data gathering.

| Case                          | Description                                                                                      |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `.all`                        | Gather code coverage data for all targets in workspace.                                          |
| `.relevant`                   | Enable code coverage for targets that have enabled code coverage in any of schemes in workspace. |
| `.targets([TargetReference])` | Gather code coverage for specified target references.                                            |
| `.none`                       | Do not gather code coverage data.                                                                |

### TestingOptions

Allows you to define which set of testing options are applied on autogenerated schemes.

| Option                     | Description                                       |
| -------------------------- | ------------------------------------------------- |
| `.parallelizable`          | Enables parallel test execution (where possible). |
| `.randomExecutionOrdering` | Randomizes order of execution of tests            |
