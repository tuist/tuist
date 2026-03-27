---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# 目录结构 {#directory-structure}

尽管 Tuist 项目通常用于取代 Xcode 项目，但它们并不局限于这种使用情况。Tuist 项目还可用于生成其他类型的项目，如 SPM
包、模板、插件和任务。本文档将介绍 Tuist 项目的结构以及如何组织这些项目。在后面的章节中，我们将介绍如何定义模板、插件和任务。

## 标准图易斯特项目 {#standard-tuist-projects}

Tuist 项目是**Tuist 生成的最常见的项目类型。** 它们用于构建应用程序、框架和库等。与 Xcode 项目不同，Tuist 项目是用 Swift
定义的，这使得它们更加灵活、更易于维护。Tuist 项目也更具声明性，因此更易于理解和推理。以下结构显示了生成 Xcode 项目的典型 Tuist 项目：

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **Tuist 目录：** 该目录有两个目的。首先，它是**项目根目录的信号** 。这样就可以构建相对于项目根目录的路径，也可以从项目中的任何目录运行
  Tuist 命令。其次，它是以下文件的容器：
  - **ProjectDescriptionHelpers：** 该目录包含所有清单文件共享的 Swift 代码。清单文件可以`导入
    ProjectDescriptionHelpers` ，以使用该目录中定义的代码。共享代码有助于避免重复并确保各项目之间的一致性。
  - **Package.swift：** 该文件包含 Swift 软件包依赖项，以便 Tuist 使用可配置和优化的 Xcode 项目和目标（如
    [CocoaPods](https://cococapods)）对其进行集成。了解更多信息<LocalizedLink href="/guides/features/projects/dependencies">，请点击这里</LocalizedLink>。

- **根目录** ：项目根目录，其中还包含`Tuist` 目录。
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>该文件包含
    Tuist 的配置，可在所有项目、工作区和环境中共享。例如，它可用于禁用方案的自动生成，或定义项目的部署目标。
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>此清单表示
    Xcode 工作区。它用于对其他项目进行分组，也可添加其他文件和方案。
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>此清单代表一个
    Xcode 项目。它用于定义项目中的目标及其依赖关系。

与上述项目交互时，命令希望在工作目录或通过`--path` 标志指示的目录中找到`Workspace.swift` 或`Project.swift`
文件。清单应位于包含`Tuist` 目录（代表项目根目录）的目录或子目录中。

::: tip
<!-- -->
Xcode 工作区允许将项目拆分成多个 Xcode 项目，以减少合并冲突的可能性。如果这正是您使用工作区的目的，那么在 Tuist
中您就不需要它们了。Tuist 会自动生成一个工作区，其中包含一个项目及其依赖项目。
<!-- -->
:::

## Swift 软件包 <Badge type="warning" text="beta" />{#swift-package-badge-typewarning-textbeta-}

Tuist 还支持 SPM 软件包项目。如果您正在开发 SPM 软件包，则无需更新任何内容。Tuist 会自动获取您的根`Package.swift`
，Tuist 的所有功能都会像`Project.swift` 清单一样工作。

要开始使用，请在您的 SPM 包中运行`tuist install` 和`tuist generate` 。现在，您的项目应该拥有与 Xcode SPM
集成中相同的方案和文件。不过，现在您还可以运行 <LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink> 并对大部分 SPM 依赖项和模块进行预编译，从而使后续的编译速度极快。
