---
{
  "title": "代码共享",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何在清单文件之间共享代码，以减少重复并确保一致性"
}
---
# 代码共享 {#code-sharing}

在大型项目中使用 Xcode 时，其中一个不便之处是它不允许通过 `.xcconfig` 文件重用除构建设置之外的项目元素。能够重用项目定义有以下好处：

- 简化**维护**，因为可以在一处应用更改，所有项目会自动获得这些更改。
- 可以定义新项目可遵循的**约定**。
- 项目更加**一致**，因此因不一致导致构建失败的可能性显著降低。
- 添加新项目变得轻松，因为我们可以重用现有逻辑。

借助**项目描述助手**的概念，Tuist 支持在清单文件之间重用代码。

> [!TIP]
> **Tuist 的独特优势**
>
> 许多组织青睐 Tuist，因为他们将项目描述助手视为平台团队将自身约定编码化、并打造描述项目的专属语言的平台。例如，基于 YAML 的项目生成器必须提出自己的基于 YAML 的专有模板方案，或迫使组织在其之上构建工具。


## 项目描述助手 {#project-description-helpers}

项目描述助手是会被编译为模块 `ProjectDescriptionHelpers` 的 Swift 文件，清单文件可以导入该模块。该模块通过收集 `Tuist/ProjectDescriptionHelpers` 目录中的所有文件进行编译。

你可以在文件顶部添加 import 语句，将它们导入到清单文件中：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` 可在以下清单中使用：
- `Project.swift`
- `Package.swift`（仅在 `#TUIST` 编译器标志下可用）
- `Workspace.swift`

## 示例 {#example}

下面的代码片段展示了我们如何扩展 `Project` 模型以添加静态构造方法，以及如何在 `Project.swift` 文件中使用它们：

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

> [!TIP]
> **建立约定的工具**
>
> 请注意，我们通过该函数定义了关于目标名称、Bundle 标识符和文件夹结构的约定。
