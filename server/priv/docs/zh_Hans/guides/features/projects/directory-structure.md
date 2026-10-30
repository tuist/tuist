---
{
  "title": "目录结构",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解 Tuist 项目的结构以及如何组织它们。"
}
---
# 目录结构 {#directory-structure}

虽然 Tuist 项目通常用于替代 Xcode 项目，但它们并不局限于这一用途。Tuist 项目还可用于生成其他类型的项目，例如 SPM 包、模板、插件和任务。本文档介绍了 Tuist 项目的结构以及如何组织它们。在后续章节中，我们将介绍如何定义模板、插件和任务。

## 标准 Tuist 项目 {#standard-tuist-projects}

Tuist 项目是**Tuist 生成的最常见项目类型。** 它们用于构建应用程序、框架和库等。与 Xcode 项目不同，Tuist 项目使用 Swift 定义，这使它们更加灵活且更易于维护。Tuist 项目也更加声明式，从而更易于理解和推理。以下结构展示了一个生成 Xcode 项目的典型 Tuist 项目：

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

- **Tuist 目录：** 该目录有两个用途。首先，它标示**项目的根目录位置**。这使得可以构建相对于项目根目录的路径，并允许从项目内的任何目录运行 Tuist 命令。其次，它是以下文件的容器：
  - **ProjectDescriptionHelpers：** 此目录包含在所有清单文件之间共享的 Swift 代码。清单文件可以`import ProjectDescriptionHelpers`以使用在此目录中定义的代码。共享代码有助于避免重复并确保各项目之间的一致性。
  - **Package.swift：** 此文件包含 Swift Package 依赖项，Tuist 使用 Xcode 项目和目标（如[CocoaPods](https://cococapods)）集成这些依赖项，使其可配置且可优化。了解更多<.localized_link href="/guides/features/projects/dependencies">此处</.localized_link>。

- **根目录**：项目的根目录，其中也包含`Tuist`目录。
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift：</bold></.localized_link>此文件包含适用于所有项目、工作区和环境的 Tuist 配置。例如，它可以用于禁用方案的自动生成，或定义项目的部署目标。
  - <.localized_link href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift：</bold></.localized_link>此清单表示一个 Xcode 工作区。它用于将其他项目分组，还可以添加额外的文件和方案。
  - <.localized_link href="/guides/features/projects/manifests#project-swift"><bold>Project.swift：</bold></.localized_link>此清单表示一个 Xcode 项目。它用于定义属于该项目的目标及其依赖项。

在与上述项目交互时，命令期望在工作目录或通过`--path`标志指定的目录中找到`Workspace.swift`或`Project.swift`文件。清单应位于包含`Tuist`目录的目录或其子目录中，该目录代表项目的根目录。

> [!TIP]
> Xcode 工作区允许将项目拆分为多个 Xcode 项目，以减少合并冲突的可能性。如果你之前使用工作区是为了这个目的，那么在 Tuist 中你不需要它们。Tuist 会自动生成一个包含项目及其依赖项项目的工作区。


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist 还支持 SPM 包项目。如果你正在处理 SPM 包，则无需更新任何内容。Tuist 会自动识别你的根`Package.swift`，并且 Tuist 的所有功能都像它是一个`Project.swift`清单一样工作。

要开始使用，请在你的 SPM 包中运行`tuist install`和`tuist generate`。你的项目现在应该具有与原生 Xcode SPM 集成中看到的相同方案和文件。不过，你现在还可以运行<.localized_link href="/guides/features/cache">`tuist cache`</.localized_link>，并使大多数 SPM 依赖项和模块预编译，从而使后续构建速度极快。
