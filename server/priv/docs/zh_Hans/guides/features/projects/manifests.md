---
{
  "title": "清单文件",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "用于定义 Tuist 项目、工作区和生成配置的清单文件。"
}
---
# 清单 {#manifests}

Tuist 默认使用 Swift 文件作为定义项目和工作区以及配置生成过程的主要方式。这些文件在整个文档中被称为**清单文件**。

选择使用 Swift 的灵感来自[Swift Package Manager](https://www.swift.org/documentation/package-manager/)，它也使用 Swift 文件来定义包。借助 Swift，我们可以利用编译器验证内容的正确性并在不同清单文件之间复用代码，同时利用 Xcode 通过语法高亮、自动补全和验证提供一流的编辑体验。

> [!NOTE]
> **缓存**
>
> 由于清单文件是需要编译的 Swift 文件，Tuist 会缓存编译结果以加快解析过程。因此，你会注意到首次运行 Tuist 时，生成项目可能需要更长时间。后续运行会更快。


## Project.swift {#projectswift}

[`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project)清单用于声明一个 Xcode 项目。项目会在清单文件所在目录中生成，名称由`name`属性指定。

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!WARNING]
> **根变量**
>
> 清单根级别应仅包含`let project = Project(...)`这一个变量。如果需要在清单的不同部分复用代码，可以使用 Swift 函数。


## Workspace.swift {#workspaceswift}

默认情况下，Tuist 会生成一个包含正在生成的项目及其依赖项目的[Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)。如果出于任何原因你希望自定义工作区以添加其他项目或包含文件和组，可以通过定义[`Workspace.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/workspace)清单来实现。

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
> Tuist 会解析依赖图并将依赖的项目包含在工作区中。你无需手动添加它们。这是构建系统正确解析依赖所必需的。


### 多项目或单项目 {#multi-or-monoproject}

常见的问题之一是应该在工作区中使用单个项目还是多个项目。在没有 Tuist 的环境中，单项目设置往往会导致频繁的 Git 冲突，因此通常建议使用工作区。然而，由于我们不建议将 Tuist 生成的 Xcode 项目纳入 Git 仓库，Git 冲突不再是问题。因此，选择在工作区中使用单个项目还是多个项目取决于你。

在 Tuist 项目中，我们倾向于使用单项目，因为冷生成速度更快（需要编译的清单文件更少），并且我们将<.localized_link href="/guides/features/projects/code-sharing">项目描述助手</.localized_link>作为封装单元。不过，你可能希望使用 Xcode 项目作为封装单元来表示应用的不同领域，这与 Xcode 推荐的项目结构更为一致。

## Tuist.swift {#tuistswift}

Tuist 提供<.localized_link href="/contributors/principles#default-to-conventions">合理的默认值</.localized_link>以简化项目配置。不过，你可以通过在项目根目录定义[`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)来自定义配置，Tuist 会使用它来确定项目的根目录。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
