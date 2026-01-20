---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# 代码共享{#code-sharing}

当我们在大型项目中使用 Xcode 时，它的一个不便之处在于，除了通过`.xcconfig`
文件进行构建设置外，它不允许重复使用项目的其他元素。由于以下原因，重复使用项目定义非常有用：

- 它简化了**维护** ，因为变更可以在一个地方应用，而且所有项目都能自动获得变更。
- 它使**公约** 的定义成为可能，新项目可以遵守这些公约。
- 项目的**更为一致** ，因此因不一致而导致构建失败的可能性大大降低。
- 由于我们可以重复使用现有的逻辑，因此添加新项目变得轻而易举。

借助**项目描述助手** 这一概念，Tuist 可以在清单文件中重复使用代码。

::: tip A TUIST UNIQUE ASSET
<!-- -->
许多组织之所以喜欢 Tuist，是因为他们从项目描述助手中看到了一个平台，平台团队可以通过这个平台编纂自己的约定，并提出自己的项目描述语言。例如，基于 YAML
的项目生成器必须提出自己的基于 YAML 的专用模板解决方案，或者迫使组织在此基础上构建自己的工具。
<!-- -->
:::

## 项目描述助手{#project-description-helpers}

项目描述助手是 Swift 文件，会被编译成一个模块`ProjectDescriptionHelpers`
，清单文件可以导入该模块。该模块通过收集`Tuist/ProjectDescriptionHelpers` 目录中的所有文件进行编译。

您可以在文件顶部添加导入语句，将它们导入清单文件：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` 在以下清单中提供：
- `Project.swift`
- `Package.swift` （仅在`#TUIST` 编译器标志后面）
- `工作区.swift`

## 示例{#example}

下面的代码段包含一个示例，说明我们如何扩展`Project` 模型以添加静态构造函数，以及如何从`Project.swift` 文件中使用这些构造函数：

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
请注意我们是如何通过该函数定义目标名称、捆绑标识符和文件夹结构的。
<!-- -->
:::
