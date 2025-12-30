---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# 表现形式{#manifests}

Tuist 默认将 Swift 文件作为定义项目和工作区以及配置生成流程的主要方式。这些文件在整个文档中被称为**manifest files** 。

决定使用 Swift 的灵感来自[Swift
包管理器](https://www.swift.org/documentation/package-manager/)，它也使用 Swift
文件来定义包。由于使用了 Swift，我们可以利用编译器来验证内容的正确性，并在不同的清单文件中重复使用代码，还可以利用 Xcode
的语法高亮显示、自动完成和验证功能来提供一流的编辑体验。

::: info CACHING
<!-- -->
由于清单文件是需要编译的 Swift 文件，Tuist 会缓存编译结果，以加快解析过程。因此，第一次运行 Tuist
时，生成项目的时间可能会稍长一些。之后的运行速度会更快。
<!-- -->
:::

## Project.swift{#projectswift}

<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
清单声明了一个 Xcode 项目。项目将在清单文件所在的同一目录中生成，其名称在`name` 属性中指明。

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning ROOT VARIABLES
<!-- -->
清单根部唯一的变量是`let project = Project(...)` 。如果需要在清单的不同部分重复使用代码，可以使用 Swift 函数。
<!-- -->
:::

## 工作区.swift{#workspaceswift}

默认情况下，Tuist 会生成一个 [Xcode
工作区](https://developer.apple.com/documentation/xcode/projects-and-workspaces)，其中包含正在生成的项目及其依赖项目。如果出于任何原因，您想自定义工作区以添加其他项目或包含文件和组，可以通过定义
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
清单来实现。

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

信息
<!-- -->
Tuist 将解析依赖关系图，并将依赖关系的项目包含在工作区中。您无需手动包含它们。这是构建系统正确解析依赖关系所必需的。
<!-- -->
:::

### 多项目或单项目{#multi-or-monoproject}

一个经常出现的问题是，在一个工作区中使用单个项目还是多个项目。在没有 Tuist 的世界里，单项目设置会导致频繁的 Git
冲突，因此我们鼓励使用工作区。不过，由于我们不建议在 Git 仓库中包含 Tuist 生成的 Xcode 项目，因此 Git
冲突并不是问题。因此，您可以自行决定在工作区中使用单个项目还是多个项目。

在 Tuist 项目中，我们倾向于使用单项目，因为冷生成时间更快（需要编译的清单文件更少），而且我们利用
<LocalizedLink href="/guides/features/projects/code-sharing"> 项目描述助手 </LocalizedLink> 作为封装单元。不过，您可能希望使用 Xcode 项目作为封装单元，以代表应用程序的不同领域，这与 Xcode
推荐的项目结构更为接近。

## Tuist.swift{#tuistswift}

Tuist 提供了
<LocalizedLink href="/contributors/principles.html#default-to-conventions"> 合理的默认值</LocalizedLink>，以简化项目配置。不过，您也可以通过在项目根目录下定义一个
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
来自定义配置，Tuist 会使用它来确定项目的根目录。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
