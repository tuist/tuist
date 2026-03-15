---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# 迁移 XcodeGen 项目{#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一款项目生成工具，它使用 YAML 作为
[配置格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
来定义 Xcode 项目。许多组织**采用了它，试图摆脱在处理 Xcode 项目时频繁出现的 Git 冲突。** 然而，频繁的 Git
冲突只是组织面临的众多问题之一。Xcode 向开发者暴露了大量复杂细节和隐式配置，这使得在大规模环境下难以维护和优化项目。 XcodeGen
设计上无法满足这一需求，因为它只是一个生成 Xcode 项目的工具，而非项目管理工具。如果您需要一款不仅能生成 Xcode
项目，还能提供更多帮助的工具，不妨考虑 Tuist。

::: tip SWIFT OVER YAML
<!-- -->
许多组织也倾向于将 Tuist 作为项目生成工具，因为它采用 Swift 作为配置格式。Swift 是一种开发者熟悉的编程语言，能让他们便捷地使用 Xcode
的自动补全、类型检查和验证功能。
<!-- -->
:::

以下是一些注意事项和指南，旨在帮助您将项目从 XcodeGen 迁移到 Tuist。

## 项目生成{#project-generation}

Tuist 和 XcodeGen 都提供了`generate` 命令，该命令可将您的项目声明转换为 Xcode 项目和工作区。

代码组

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

区别在于编辑体验。使用 Tuist 时，您可以运行 ``tuist edit` ` 命令，该命令会即时生成一个 Xcode
项目，您可以直接打开并开始工作。当您需要快速修改项目时，这尤其有用。

## `project.yaml` {#projectyaml}

XcodeGen的`项目.yaml` 描述文件将转换为`项目.swift` 。此外，您可以通过`工作区.swift`
自定义项目在工作区中的分组方式。您还可以创建一个项目`项目.swift`
，其中包含引用其他项目目标的目标。在这些情况下，Tuist将生成一个包含所有项目的Xcode工作区。

代码组

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

::: tip XCODE'S LANGUAGE
<!-- -->
XcodeGen 和 Tuist 都采用了 Xcode 的语言和概念。不过，Tuist 基于 Swift 的配置让您能够便捷地使用 Xcode
的自动补全、类型检查和验证功能。
<!-- -->
:::

## 模板规范{#spec-templates}

作为项目配置语言，YAML的一个缺点是它默认不支持跨 YAML 文件的复用。 在描述项目时，这通常是一个常见需求，XcodeGen
不得不通过其专有解决方案——名为* 的“模板”* 来解决。而在 Tuist 中，可复用性已内置于 Swift 语言本身，并通过名为
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink> 的 Swift 模块实现，该模块允许在所有清单文件中复用代码。

代码组
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
