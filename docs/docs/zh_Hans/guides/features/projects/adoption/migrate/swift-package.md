---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# 迁移 Swift 套件{#migrate-a-swift-package}

Swift Package
Manager最初作为Swift代码的依赖管理器出现，却意外解决了项目管理问题并支持Objective-C等其他编程语言。由于该工具的设计初衷不同，若用于大规模项目管理则存在挑战——其灵活性、性能和功能均不及Tuist。
《Bumble 的 iOS 扩展实践》一文对此有精辟论述，其中包含下表对比 Swift Package Manager 与原生 Xcode 项目的性能表现：

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

我们常遇到质疑Tuist必要性的开发者和组织，认为Swift Package
Manager能承担类似的项目管理功能。部分人尝试迁移后才发现开发体验大幅退化。例如文件重命名可能需要长达15秒才能重新索引。15秒！

**苹果是否会将Swift Package Manager打造成面向规模化的项目管理工具尚不明确。**
然而我们尚未看到任何迹象表明此事正在推进。事实上，我们观察到的情况恰恰相反。他们正沿袭Xcode的设计思路，例如通过隐式配置实现便捷操作——<LocalizedLink href="/guides/features/projects/cost-of-convenience">如您所知，</LocalizedLink>这种方式在规模化应用中往往会引发复杂问题。
我们认为苹果需要回归第一性原理，重新审视某些作为依赖管理器合理但作为项目管理器不适用的决策——例如使用编译型语言作为定义项目的接口。

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist将Swift Package Manager视为依赖管理器，且表现优异。我们用它来解析依赖关系并构建项目。我们不将其用于定义项目，因为它并非为此设计。
<!-- -->
:::

## 从 Swift Package Manager 迁移至 Tuist{#migrating-from-swift-package-manager-to-tuist}

Swift Package
Manager与Tuist的相似性使得迁移过程非常简单。主要区别在于：您将使用Tuist的DSL定义项目，而非`的Package.swift` 。

首先，在`Package.swift` 文件旁边创建`Project.swift` 文件。`Project.swift`
文件将包含项目的定义。以下是一个定义单一目标的`Project.swift` 文件示例：

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

- **项目描述**: 替代使用`软件包描述` 的方式，您将使用`项目描述` 。
- **项目：** 您将导出的是`项目实例` ，而非`包实例` 。
- **Xcode语言：** 定义项目时使用的原始元素模仿Xcode的语言结构，因此你会看到方案、目标、构建阶段等术语。

然后创建名为 Tuist.swift 的文件（位于`目录下），内容如下：`

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 文件包含项目配置信息，其路径将作为确定项目根目录的参考依据。您可查阅
<LocalizedLink href="/guides/features/projects/directory-structure">目录结构</LocalizedLink>文档以深入了解Tuist项目的结构体系。

## 编辑项目{#editing-the-project}

可使用 <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> 在 Xcode 中编辑项目。该命令将生成可直接打开并开始工作的 Xcode 项目。

```bash
tuist edit
```

根据项目规模，可选择一次性或分阶段实施。建议从小型项目入手熟悉DSL及工作流程。我们的建议始终是：从依赖度最高的子目标开始，逐步推进至顶级目标。
