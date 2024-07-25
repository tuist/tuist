---
title: Manifests
description: Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process.
---

# Manifests

Tuist defaults to Swift files as the primary way to define projects and workspaces and configure the generation process. These files are referred to as **manifest files** throughout the documentation. 

The decision of using Swift was inspired by the [Swift Package Manager](https://www.swift.org/documentation/package-manager/), which also uses Swift files to define packages. Thanks to the usage of Swift, we can leverage the compiler to validate the correctness of the content and reuse code across different manifest files, and Xcode to provide a first-class editing experience thanks to the syntax highlighting, auto-completion, and validation.

> [!NOTE] CACHING
> Since manifest files are Swift files that need to be compiled, Tuist caches the compilation results to speed up the parsing process. Therefore, you'll notice that the first time you run Tuist, it might take a bit longer to generate the project. Subsequent runs will be faster.

## Project.swift

The [`Project.swift`](/references/project-description/structs/project) manifest declares an Xcode project. The project gets generated in the same directory where the manifest file is located with the name indicated in the `name` property.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!WARNING] ROOT VARIABLES
> The only variable that should be at the root of the manifest is `let project = Project(...)`. If you need to reuse code across various parts of the manifest, you can use Swift functions.

## Workspace.swift

By default, Tuist generates an [Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces) containing the project being generated and the projects of its dependencies. If for any reason you'd like to customize the workspace to add additional projects or include files and groups, you can do so by defining a [`Workspace.swift`](/references/project-description/structs/workspace) manifest.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

> [!NOTE]
> Tuist will resolve the dependency graph and include the projects of the dependencies in the workspace. You don't need to include them manually. This is necessary for the build system to resolve the dependencies correctly.

### Multi or mono-project

A question that often comes up is whether to use a single project or multiple projects in a workspace. In a world without Tuist where a mono-project setup would lead to frequent Git conflicts the usage of workspaces is encouraged. However, since we don't recommend including the Tuist-generated Xcode projects in the Git repository, Git conflicts are not an issue. Therefore, the decision of using a single project or multiple projects in a workspace is up to you.

In the Tuist project we lean on mono-projects because the cold generation time is faster (fewer manifest files to compile) and we leverage [project description helpers](/guides/develop/projects/code-sharing) as a unit of encapsulation. However, you might want to use Xcode projects as a unit of encapsulation to represent different domains of your application, which aligns more closely with the Xcode's recommended project structure.

## Config.swift

Tuist provides [sensible defaults](/contributors/principles.html#default-to-conventions) to simplify project configuration. However, you can customize the configuration by defining a [`Config.swift`](/references/project-description/structs/config) manifest under the `Tuist` directory, which is used by Tuist to determine the root of the project.

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(enforceExplicitDependencies: true)
)
```