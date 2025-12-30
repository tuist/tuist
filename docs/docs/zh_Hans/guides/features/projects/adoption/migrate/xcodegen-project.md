---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# 迁移 XcodeGen 项目{#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一款项目生成工具，它使用 YAML
作为[一种配置格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)来定义
Xcode 项目。许多组织**都采用了该工具，试图摆脱在处理 Xcode 项目时频繁出现的 Git 冲突。** 然而，频繁的 Git
冲突只是企业遇到的众多问题之一。Xcode 为开发人员提供了大量错综复杂的隐含配置，这使得大规模维护和优化项目变得十分困难。XcodeGen
在设计上存在不足，因为它只是一个生成 Xcode 项目的工具，而不是一个项目管理器。如果您除了需要一个生成 Xcode
项目的工具外，还需要一个其他的工具，那么您可以考虑 Tuist。

::: tip SWIFT OVER YAML
<!-- -->
许多组织也喜欢将 Tuist 作为项目生成工具，因为它使用 Swift 作为配置格式。Swift 是一种开发人员非常熟悉的编程语言，可以方便地使用 Xcode
的自动完成、类型检查和验证功能。
<!-- -->
:::

以下是一些注意事项和指南，可帮助您将项目从 XcodeGen 移植到 Tuist。

## 项目生成{#project-generation}

Tuist 和 XcodeGen 都提供了一个`生成` 命令，可将项目声明转化为 Xcode 项目和工作区。

代码组

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

不同之处在于编辑体验。使用 Tuist，您可以运行`tuist edit` 命令，该命令会即时生成一个 Xcode
项目，您可以打开并开始工作。当您想对项目进行快速修改时，这一点尤其有用。

## `project.yaml` {#projectyaml}

XcodeGen 的`project.yaml` 描述文件变为`Project.swift` 。此外，您还可以使用`Workspace.swift`
来自定义项目在工作区中的分组方式。您也可以让项目`Project.swift` 包含引用其他项目目标的目标。在这种情况下，Tuist 将生成一个包含所有项目的
Xcode 工作区。

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
XcodeGen 和 Tuist 都采用了 Xcode 的语言和概念。不过，Tuist 基于 Swift 的配置为您提供了使用 Xcode
的自动完成、类型检查和验证功能的便利。
<!-- -->
:::

## 规格模板{#spec-templates}

YAML 作为项目配置语言的一个缺点是，它不支持开箱即用的 YAML 文件之间的复用。这是描述项目时的一个常见需求，XcodeGen
不得不使用自己的专利解决方案（名为*"templates"* ）来解决这个问题。Tuist 的可重用性内置于 Swift 语言本身，并通过名为
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink> 的 Swift 模块实现，该模块允许在所有清单文件中重用代码。

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
