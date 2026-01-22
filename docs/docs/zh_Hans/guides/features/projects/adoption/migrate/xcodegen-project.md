---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# 迁移XcodeGen项目{#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一款采用 YAML
作为[配置格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)来定义
Xcode 项目的生成工具。许多组织**采用它以期摆脱处理 Xcode 项目时频繁出现的 Git 冲突问题。** 然而，频繁的 Git
冲突只是组织面临的众多问题之一。Xcode 向开发者暴露了大量复杂细节和隐式配置，使得项目在规模化维护和优化时困难重重。
XcodeGen在设计上存在局限，因为它本质上是生成Xcode项目的工具而非项目管理器。若您需要超越项目生成范畴的解决方案，Tuist或许值得考虑。

::: tip SWIFT OVER YAML
<!-- -->
许多组织也青睐 Tuist 作为项目生成工具，因为它采用 Swift 作为配置格式。Swift 是开发者熟悉的编程语言，能让他们便捷地使用 Xcode
的自动补全、类型检查和验证功能。
<!-- -->
:::

以下是一些注意事项和指南，可帮助您将项目从 XcodeGen 迁移至 Tuist。

## 项目生成{#project-generation}

Tuist 和 XcodeGen 均提供 ``` 生成 `` ` 的命令，可将项目声明转换为 Xcode 项目和工作区。

代码组

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

差异在于编辑体验。使用Tuist时，可执行`tuist edit`
命令，该命令会即时生成Xcode项目供您直接打开并开始工作。当您需要快速修改项目时，此功能尤为实用。

## `project.yaml` {#projectyaml}

XcodeGen的`项目.yaml文件` 描述文件将生成`项目.swift文件` 。此外，您可通过`工作区.swift文件`
自定义项目在工作区中的分组方式。您还可创建包含目标的项目`项目.swift文件`
，这些目标会引用其他项目的目标。在这些情况下，Tuist将生成包含所有项目的Xcode工作区。

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
XcodeGen与Tuist均遵循Xcode的语言规范与设计理念。但Tuist基于Swift的配置方案，可让您便捷地使用Xcode的自动补全、类型检查及验证功能。
<!-- -->
:::

## 规范模板{#spec-templates}

YAML作为项目配置语言的缺点之一在于，它无法原生支持跨YAML文件的复用性。
在描述项目时，这种需求十分常见。XcodeGen为此开发了专有解决方案*"模板"*
。而Tuist通过Swift语言本身及名为<LocalizedLink href="/guides/features/projects/code-sharing">项目描述辅助工具</LocalizedLink>的Swift模块实现了内置复用性，使代码能在所有清单文件中复用。

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
