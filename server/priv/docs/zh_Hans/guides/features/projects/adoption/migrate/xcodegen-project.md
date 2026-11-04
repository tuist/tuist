---
{
  "title": "迁移 XcodeGen 项目",
  "titleTemplate": ":title · 迁移 · 采用 · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何将项目从 XcodeGen 迁移到 Tuist。"
}
---
# 迁移 XcodeGen 项目 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一款项目生成工具，它使用 YAML 作为[配置格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)来定义 Xcode 项目。许多组织**采用它是为了摆脱在处理 Xcode 项目时频繁出现的 Git 冲突。** 然而，频繁的 Git 冲突只是组织面临的众多问题之一。Xcode 向开发者暴露了大量复杂细节和隐式配置，使得在大规模下维护和优化项目变得困难。XcodeGen 在这方面存在设计局限，因为它是一个生成 Xcode 项目的工具，而不是项目管理器。如果你需要一个不仅能生成 Xcode 项目还能提供更多帮助的工具，可以考虑 Tuist。

> [!TIP]
> **Swift 优于 YAML**
>
> 许多组织也倾向于将 Tuist 作为项目生成工具，因为它使用 Swift 作为配置格式。Swift 是开发者熟悉的编程语言，能够让他们方便地使用 Xcode 的自动补全、类型检查和验证功能。


以下是一些注意事项和指南，帮助你将从 XcodeGen 迁移到 Tuist。

## 项目生成 {#project-generation}

Tuist 和 XcodeGen 都提供 `generate` 命令，可将你的项目声明转换为 Xcode 项目和 workspace。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

区别在于编辑体验。使用 Tuist，你可以运行 `tuist edit` 命令，它会即时生成一个 Xcode 项目，你可以打开并开始工作。这在需要快速修改项目时特别有用。

## `project.yaml` {#projectyaml}

XcodeGen 的 `project.yaml` 描述文件会变为 `Project.swift`。此外，你可以使用 `Workspace.swift` 来自定义项目在 workspace 中的分组方式。你还可以创建一个包含引用其他项目目标的 target 的项目 `Project.swift`。在这种情况下，Tuist 将生成一个包含所有项目的 Xcode Workspace。

::: code-group

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist.swift
  Project.swift
  Workspace.swift
```
<!-- -->
:::

> [!TIP]
> **Xcode 的语言**
>
> XcodeGen 和 Tuist 都遵循 Xcode 的语言和概念。不过，Tuist 基于 Swift 的配置让你能够方便地使用 Xcode 的自动补全、类型检查和验证功能。


## 规范模板 {#spec-templates}

YAML 作为项目配置语言的一个缺点是，它默认不支持跨 YAML 文件复用。这在描述项目时是一种常见需求，XcodeGen 不得不通过其专有的 *“模板”* 解决方案来解决。而在 Tuist 中，复用能力内置于语言本身（Swift），并通过名为<.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link>的 Swift 模块实现，它允许你在所有清单文件中复用代码。

::: code-group
```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```
```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
