---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# 代码共享{#code-sharing}

在大型项目中使用Xcode时，其不便之处在于无法通过`.xcconfig和` 文件复用除构建设置外的项目元素。复用项目定义具有以下优势：

- 这便于维护**** ，因为只需在一个地方进行更改，所有项目就会自动获得更新。
- 这使得定义**规范** 成为可能，新项目可遵循这些规范。
- 项目采用更统一的**规范** ，因此因不一致导致构建失败的概率显著降低。
- 新增專案變得輕而易舉，因為我們能重複使用現有邏輯。

Tuist 通过项目描述辅助工具（**）实现了清单文件间的代码复用功能，详情参见：**

::: tip A TUIST UNIQUE ASSET
<!-- -->
许多组织青睐 Tuist，因为他们将项目描述助手视为平台团队制定规范、构建专属项目描述语言的平台。例如，基于 YAML 的项目生成器必须开发专属的 YAML
模板解决方案，否则将迫使组织在其工具基础上进行构建。
<!-- -->
:::

## 项目描述助手{#project-description-helpers}

项目描述辅助工具是Swift文件，编译后形成模块`ProjectDescriptionHelpers`
，供清单文件导入。该模块通过收集`Tuist/ProjectDescriptionHelpers` 目录下的所有文件进行编译。

您可在文件开头添加导入语句将其导入清单文件：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` 可在以下清单中使用：
- `Project.swift`
- `Package.swift` (仅在启用`#TUIST` 编译器标志时生效)
- `Workspace.swift`

## 示例{#example}

以下代码片段展示了如何扩展`项目` 的模型以添加静态构造函数，以及如何在`项目.swift` 文件中使用它们：

代码组
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

::: tip A TOOL TO ESTABLISH CONVENTIONS
<!-- -->
注意：通过该函数，我们定义了目标名称、包标识符及文件夹结构的相关规范。
<!-- -->
:::
