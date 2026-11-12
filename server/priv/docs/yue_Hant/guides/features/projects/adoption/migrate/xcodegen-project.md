---
{
  "title": "遷移 XcodeGen 項目",
  "titleTemplate": ":title · 遷移 · 採用 · 項目 · 功能 · 指南 · Tuist",
  "description": "了解如何將你的項目從 XcodeGen 遷移至 Tuist。"
}
---
# 遷移 XcodeGen 項目 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一個項目生成工具，使用 YAML 作為 [配置格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) 來定義 Xcode 項目。許多組織 **採用它是為了避免在使用 Xcode 項目時經常出現的 Git 衝突。** 然而，頻繁的 Git 衝突只是組織面臨的眾多問題之一。Xcode 向開發人員暴露了許多複雜性和隱式配置，使得在大規模下維護和優化項目變得困難。XcodeGen 在這方面存在設計上的不足，因為它是一個生成 Xcode 項目的工具，而不是項目管理器。如果你需要一個不僅能幫助你生成 Xcode 項目的工具，你可以考慮 Tuist。

> [!TIP]
> **Swift 勝於 YAML**
>
> 許多組織也偏好將 Tuist 作為項目生成工具，因為它使用 Swift 作為配置格式。Swift 是一種開發人員熟悉的編程語言，並為他們提供了使用 Xcode 自動補全、類型檢查和驗證功能的便利。


以下是一些注意事項和指南，幫助你將項目從 XcodeGen 遷移到 Tuist。

## 項目生成 {#project-generation}

Tuist 和 XcodeGen 都提供了一個 `generate` 命令，將你的項目聲明轉換為 Xcode 項目和工作區。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

區別在於編輯體驗。使用 Tuist，你可以運行 `tuist edit` 命令，它會即時生成一個 Xcode 項目，你可以打開並開始工作。這在你想要對項目進行快速更改時特別有用。

## `project.yaml` {#projectyaml}

XcodeGen 的 `project.yaml` 描述文件變成了 `Project.swift`。此外，你可以使用 `Workspace.swift` 來自定義項目在工作區中的分組方式。你還可以有一個項目 `Project.swift`，其中的目標引用其他項目的目標。在這些情況下，Tuist 將生成一個包含所有項目的 Xcode 工作區。

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
> **Xcode 的語言**
>
> XcodeGen 和 Tuist 都採用了 Xcode 的語言和概念。然而，Tuist 基於 Swift 的配置為你提供了使用 Xcode 自動補全、類型檢查和驗證功能的便利。


## 規範模板 {#spec-templates}

YAML 作為項目配置語言的缺點之一是它不支持跨 YAML 文件的開箱即用重用。這在描述項目時是一個常見需求，XcodeGen 不得不通過其專有的解決方案 *「模板」* 來解決。而 Tuist 的重用性內置於語言本身（Swift）中，並通過名為 <.localized_link href="/guides/features/projects/code-sharing">項目描述助手</.localized_link> 的 Swift 模塊實現，允許在所有清單文件中重用代碼。

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
import ProjectDescriptionHelpers

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature"))
```
:::
