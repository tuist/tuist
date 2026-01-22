---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# 表现形式{#manifests}

Tuist默认以Swift文件作为定义项目和工作区、配置生成流程的主要方式。文档中将这些文件统称为**清单文件** 。

选择Swift的契机源于[Swift Package
Manager](https://www.swift.org/documentation/package-manager/)——该工具同样采用Swift文件定义包。得益于Swift语言特性，我们能借助编译器验证内容正确性，实现跨清单文件的代码复用，并通过Xcode的语法高亮、自动补全及验证功能获得一流的编辑体验。

::: info CACHING
<!-- -->
由于清单文件是需要编译的 Swift 文件，Tuist 会缓存编译结果以加速解析过程。因此您会发现首次运行 Tuist
时，项目生成可能需要稍长时间。后续运行将更快。
<!-- -->
:::

## Project.swift{#projectswift}

<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
该清单文件声明了一个Xcode项目。项目将生成在清单文件所在目录下，其名称由`name属性` 指定。

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
清单根目录下仅应包含变量：`let project = Project(...)` 若需在清单不同部分复用代码，可使用Swift函数。
<!-- -->
:::

## 工作区.swift{#workspaceswift}

默认情况下，Tuist会生成包含目标项目及其依赖项的[Xcode工作区](https://developer.apple.com/documentation/xcode/projects-and-workspaces)。若需自定义工作区以添加额外项目或包含文件/组，可通过定义<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>清单文件实现。

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
Tuist将解析依赖关系图，并将依赖项的项目纳入工作区。您无需手动添加这些项目。此操作对构建系统正确解析依赖关系至关重要。
<!-- -->
:::

### 多项目或单项目{#multi-or-monoproject}

一个常见问题是：工作区中应使用单个项目还是多个项目？在没有Tuist的环境中，单项目配置会导致频繁的Git冲突，因此建议使用工作区。但由于我们不推荐将Tuist生成的Xcode项目纳入Git仓库，Git冲突便不再是问题。因此，工作区中采用单项目或多项目模式的选择权完全取决于您。

在 Tuist 项目中，我们倾向于采用单项目模式，因为其冷启动时间更短（需编译的清单文件更少），且我们利用
<LocalizedLink href="/guides/features/projects/code-sharing">项目描述辅助工具</LocalizedLink>作为封装单元。不过，您可能希望使用
Xcode 项目作为封装单元来表示应用的不同领域，这更符合 Xcode 推荐的项目结构。

## Tuist.swift{#tuistswift}

Tuist提供<LocalizedLink href="/contributors/principles.html#default-to-conventions">合理的默认设置</LocalizedLink>以简化项目配置。但您可通过在项目根目录定义<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>来自定义配置，Tuist将以此确定项目根目录。

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
