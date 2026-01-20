---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# 迁移 Swift 软件包{#migrate-a-swift-package}

Swift Package Manager 是作为 Swift 代码的依赖关系管理器出现的，它无意中解决了管理项目和支持 Objective-C
等其他编程语言的问题。由于该工具在设计之初就考虑到了不同的目的，因此使用它来大规模管理项目可能具有挑战性，因为它缺乏 Tuist
所提供的灵活性、性能和功能。这一点在[Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)一文中得到了很好的体现，文章中的下表比较了
Swift 包管理器和原生 Xcode 项目的性能：

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

我们经常会遇到一些开发人员和组织质疑 Tuist 的必要性，认为 Swift
包管理器也可以发挥类似的项目管理作用。有些人冒险进行迁移，但后来发现开发人员的体验明显下降。例如，重命名一个文件可能需要 15 秒才能重新索引。15 秒

**苹果是否会让 Swift Package Manager 成为内置的大规模项目管理器，目前还不确定。**
不过，我们没有看到任何迹象表明这种情况正在发生。事实上，我们看到的恰恰相反。他们正在做出受 Xcode
启发的决定，比如通过隐式配置来实现便利性，而隐式配置<LocalizedLink href="/guides/features/projects/cost-of-convenience">可能是大规模复杂性的根源</LocalizedLink>。我们认为，苹果应该遵循第一原则，重新审视一些作为依赖关系管理器而非项目管理器的决策，例如使用编译语言作为定义项目的接口。

::: tip SPM IS A DEPENDENCY MANAGER
<!-- -->
Tuist 将 Swift
软件包管理器视为依赖关系管理器，它是一个很棒的管理器。我们用它来解决依赖关系并构建它们。我们不用它来定义项目，因为它不是为此而设计的。
<!-- -->
:::

## 从 Swift 包管理器迁移到 Tuist{#migrating-from-swift-package-manager-to-tuist}

Swift 软件包管理器和 Tuist 之间的相似之处使得迁移过程简单明了。主要区别在于，您将使用 Tuist 的 DSL 而不是`Package.swift`
来定义项目。

首先，在`Package.swift` 文件旁边创建`Project.swift` 文件。`Project.swift`
文件将包含项目定义。下面是`Project.swift` 文件的示例，该文件定义了一个具有单一目标的项目：

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

有些事情需要注意：

- **ProjectDescription** ：不要使用`PackageDescription` ，而是使用`ProjectDescription` 。
- **项目：** 导出的不是`软件包` 实例，而是`项目` 实例。
- **Xcode 语言：** 您用来定义项目的基元模仿 Xcode 的语言，因此您会发现方案、目标和构建阶段等。

然后创建`Tuist.swift` 文件，内容如下：

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 包含项目配置，其路径可作为确定项目根目录的参考。您可以查看
<LocalizedLink href="/guides/features/projects/directory-structure"> 目录结构 </LocalizedLink> 文档，了解 Tuist 项目结构的更多信息。

## 编辑项目{#editing-the-project}

您可以使用 <LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink> 在 Xcode 中编辑项目。该命令将生成一个 Xcode 项目，您可以打开并开始工作。

```bash
tuist edit
```

根据项目的规模，您可以考虑一次性使用或逐步使用。我们建议从小型项目开始，熟悉 DSL 和工作流程。我们的建议是，始终从最依赖的目标开始，一直到顶层目标。
