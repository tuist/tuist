---
title: Манифесты
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Узнайте про манифест файлы, которые Tuist использует, чтобы описать проекты и рабочие пространства и настроить процесс генерации.
---

# Манифесты {#manifests}

Tuist по умолчанию использует Swift файлы в качестве основного способа определения проектов и рабочих пространств, а также настройки процесса генерации. В документации эти файлы называются **манифест файлами**.

Решение использовать Swift было вдохновлено менеджером пакетов [Swift Package Manager](https://www.swift.org/documentation/package-manager/), который также использует Swift файлы для описания пакетов. Благодаря использованию Swift мы можем использовать компилятор для валидации содержимого и повторного использования кода в различных манифест файлах, а также Xcode для предоставления первоклассного опыта редактирования благодаря подсветке синтаксиса, автодополнению и валидации.

> [!NOTE] Кэширование
> Поскольку манифест файлы представляют собой файлы Swift, которые необходимо скомпилировать, Tuist кэширует результаты компиляции, чтобы ускорить процесс анализа. Поэтому вы заметите, что при первом запуске Tuist генерация проекта может занять немного больше времени. Последующие запуски будут быстрее.

## Project.swift {#projectswift}

The <LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink> manifest declares an Xcode project. The project gets generated in the same directory where the manifest file is located with the name indicated in the `name` property.

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

## Workspace.swift {#workspaceswift}

By default, Tuist generates an [Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces) containing the project being generated and the projects of its dependencies. If for any reason you'd like to customize the workspace to add additional projects or include files and groups, you can do so by defining a <LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink> manifest.

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

### Multi or mono-project {#multi-or-monoproject}

A question that often comes up is whether to use a single project or multiple projects in a workspace. In a world without Tuist where a mono-project setup would lead to frequent Git conflicts the usage of workspaces is encouraged. However, since we don't recommend including the Tuist-generated Xcode projects in the Git repository, Git conflicts are not an issue. Therefore, the decision of using a single project or multiple projects in a workspace is up to you.

In the Tuist project we lean on mono-projects because the cold generation time is faster (fewer manifest files to compile) and we leverage <LocalizedLink href="/guides/develop/projects/code-sharing">project description helpers</LocalizedLink> as a unit of encapsulation. However, you might want to use Xcode projects as a unit of encapsulation to represent different domains of your application, which aligns more closely with the Xcode's recommended project structure.

## Tuist.swift {#tuistswift}

Tuist provides <LocalizedLink href="/contributors/principles.html#default-to-conventions">sensible defaults</LocalizedLink> to simplify project configuration. However, you can customize the configuration by defining a <LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink> at the root of the project, which is used by Tuist to determine the root of the project.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
