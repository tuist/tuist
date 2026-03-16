---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# 迁移 Swift 包{#migrate-a-swift-package}

Swift Package Manager 最初作为 Swift 代码的依赖项管理器出现，却意外地解决了项目管理问题，并支持 Objective-C
等其他编程语言。由于该工具的设计初衷不同，若要将其用于大规模项目管理，可能会面临挑战，因为它缺乏 Tuist 所具备的灵活性、性能和功能。
这一点在《Bumble 的 iOS
扩展》(https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)
一文中得到了很好的体现，该文包含以下表格，对比了 Swift Package Manager 与原生 Xcode 项目的性能：

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

我们经常遇到一些开发者和组织质疑 Tuist 的必要性，认为 Swift Package Manager
可以承担类似的项目管理角色。有些人尝试迁移后，才意识到他们的开发体验大幅下降。例如，重命名一个文件可能需要长达 15 秒才能重新索引。15 秒！

**苹果是否会将 Swift Package Manager 打造成一个面向大规模应用的项目管理器尚不确定。**
然而，我们并未看到任何迹象表明此事正在发生。事实上，我们看到的恰恰相反。他们正在做出受 Xcode
启发的决策，例如通过隐式配置来追求便利性，而<LocalizedLink href="/guides/features/projects/cost-of-convenience">正如你所知，</LocalizedLink>这正是大规模应用中产生复杂性的根源。
我们认为，苹果需要回归第一性原理，重新审视那些作为依赖管理器时合理、但作为项目管理器时却不合理的决策，例如使用编译型语言作为定义项目的接口。

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist 将 Swift Package Manager
视为依赖项管理器，而且它非常出色。我们使用它来解析依赖项并进行构建。我们不使用它来定义项目，因为它并非为此设计。
<!-- -->
:::

## 从 Swift Package Manager 迁移至 Tuist{#migrating-from-swift-package-manager-to-tuist}

Swift Package
Manager与Tuist之间的相似之处使得迁移过程非常简单。主要区别在于，您将使用Tuist的DSL来定义项目，而不是`Package.swift` 。

首先，在您的`Package.swift` 文件旁边创建一个`Project.swift` 文件。`Project.swift`
文件将包含您的项目定义。以下是一个`Project.swift` 文件的示例，该文件定义了一个包含单个目标的项目：

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

注意事项：

- **ProjectDescription**: 请勿使用`PackageDescription` ，而应使用`ProjectDescription` 。
- **项目：** 您将导出一个`项目` 实例，而非导出一个`包` 实例。
- **Xcode 语言：** 您用于定义项目的基本元素模仿了 Xcode 的语言，因此您会看到方案、目标和构建阶段等内容。

然后创建一个名为 ``Tuist.swift` 的文件（路径为 `` `），内容如下：

```swift
import ProjectDescription

let tuist = Tuist()
```

`文件 Tuist.swift` 包含项目的配置信息，其路径用于确定项目的根目录。您可以查阅
<LocalizedLink href="/guides/features/projects/directory-structure">目录结构</LocalizedLink>
文档，进一步了解 Tuist 项目的结构。

## 编辑项目{#editing-the-project}

您可以使用 <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> 在 Xcode 中编辑该项目。该命令将生成一个 Xcode 项目，您可以打开并开始进行开发。

```bash
tuist edit
```

根据项目规模，您可以考虑一次性完成翻译，或分阶段进行。我们建议从小型项目入手，以熟悉 DSL
和工作流程。我们的建议是始终从依赖关系最强的目标开始，逐步向上处理至顶级目标。
