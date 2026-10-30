---
{
  "title": "迁移 Swift Package",
  "titleTemplate": ":title · 迁移 · 采用 · 项目 · 功能 · 指南 · Tuist",
  "description": "从 Swift Package Manager 项目管理迁移到 Tuist。"
}
---
# 迁移 Swift Package {#migrate-a-swift-package}

Swift Package Manager 最初是作为 Swift 代码的依赖管理器出现的，却意外地承担起了管理项目和支持 Objective-C 等其他编程语言的任务。由于该工具的设计初衷不同，它在灵活性、性能和能力方面不如 Tuist，因此难以用于大规模项目管理。[Bumble 的 iOS 规模化实践](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)一文很好地说明了这一点，其中包含以下对比 Swift Package Manager 与原生 Xcode 项目性能的表格：

<img style="max-width: 400px;" alt="对比使用 SPM 与原生 Xcode 项目时性能退化的表格" src="/images/guides/start/migrate/performance-table.webp">

我们经常遇到开发者和组织质疑是否需要 Tuist，因为 Swift Package Manager 也能承担类似的项目管理角色。有些人尝试迁移后才发现开发者体验显著下降。例如，重命名一个文件可能需要长达 15 秒才能重新建立索引。15 秒！

**Apple 是否会将 Swift Package Manager 打造为面向规模的项目管理器尚不确定。** 然而，我们并未看到任何迹象表明此事正在发生。事实上，情况恰恰相反。他们做出的决策往往受 Xcode 影响，例如通过隐式配置来换取便利，而<.localized_link href="/guides/features/projects/cost-of-convenience">正如你所知，</.localized_link>这正是大规模场景下复杂性的根源。我们认为，Apple 需要回归第一性原理，重新审视那些作为依赖管理器合理但作为项目管理器并不合适的决策，例如使用编译型语言作为定义项目的接口。

> [!TIP]
> **将 SPM 仅用作依赖管理器**
>
> Tuist 将 Swift Package Manager 视为依赖管理器，而且它在这方面表现出色。我们用它来解析和构建依赖项。我们不用它来定义项目，因为它并非为此而设计。


## 从 Swift Package Manager 迁移到 Tuist {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager 与 Tuist 的相似之处使迁移过程变得简单直接。主要区别在于，你将使用 Tuist 的 DSL 而非 `Package.swift` 来定义项目。

首先，在 `Package.swift` 文件旁边创建一个 `Project.swift` 文件。`Project.swift` 文件将包含你的项目定义。下面是一个定义单个目标的 `Project.swift` 文件示例：

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

需要注意的事项：

- **ProjectDescription**：你将使用 `ProjectDescription`，而不是 `PackageDescription`。
- **Project：** 你将导出 `project` 实例，而不是 `package` 实例。
- **Xcode 语言：** 你用于定义项目的原语模仿了 Xcode 的语言，因此你会找到 scheme、target 和构建阶段等元素。

然后创建一个包含以下内容的 `Tuist.swift` 文件：

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 包含你的项目配置，其路径作为确定项目根目录的参考。你可以查看<.localized_link href="/guides/features/projects/directory-structure">目录结构</.localized_link>文档，进一步了解 Tuist 项目的结构。

## 编辑项目 {#editing-the-project}

你可以使用<.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>在 Xcode 中编辑项目。该命令会生成一个 Xcode 项目，你可以打开它并开始工作。

```bash
tuist edit
```

根据项目规模，你可以选择一次性迁移或逐步迁移。我们建议从小型项目开始，以熟悉 DSL 和工作流程。我们的建议始终是从被依赖最多的 target 开始，逐步向上直到顶层 target。
