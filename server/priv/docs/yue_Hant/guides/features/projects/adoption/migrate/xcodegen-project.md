---
{
  "title": "遷移 XcodeGen 項目",
  "titleTemplate": ":title · 遷移 · 採用 · 項目 · 功能 · 指南 · Tuist",
  "description": "了解如何將你的項目從 XcodeGen 遷移至 Tuist。"
}
---
# 遷移 XcodeGen 項目 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 係一個項目生成工具，使用 YAML 作為 [配置格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) 嚟定義 Xcode 項目。好多機構 **採用佢，希望避免處理 Xcode 項目時經常出現嘅 Git 衝突。** 不過，頻繁嘅 Git 衝突只係機構面對嘅眾多問題之一。Xcode 令開發者要面對好多複雜性同隱式配置，難以大規模維護同優化項目。XcodeGen 喺呢方面先天不足，因為佢係一個生成 Xcode 項目嘅工具，而唔係項目管理器。如果你需要一個除咗生成 Xcode 項目之外仲可以幫到你嘅工具，你可以考慮 Tuist。你唔使遷移都可以使用 Tuist：[XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen) 解釋咗邊啲功能（例如 Xcode 快取同構建洞察）可以同 XcodeGen 項目一齊使用，以及幾時值得遷移。

> [!TIP]
> **Swift 取代 YAML**
>
> 好多機構都偏好 Tuist 作為項目生成工具，因為佢使用 Swift 作為配置格式。Swift 係開發者熟悉嘅編程語言，並且提供使用 Xcode 自動完成、類型檢查同驗證功能嘅便利。


以下係一啲考慮因素同指引，幫助你將項目由 XcodeGen 遷移到 Tuist。

## 項目生成 {#project-generation}

Tuist 同 XcodeGen 都提供 `generate` 指令，將你嘅項目聲明轉換為 Xcode 項目同工作區。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

分別在於編輯體驗。使用 Tuist，你可以運行 `tuist edit` 指令，即時生成一個 Xcode 項目，你可以打開並開始工作。當你想對項目進行快速更改時，這特別有用。

## `project.yaml` {#projectyaml}

XcodeGen 嘅 `project.yaml` 描述文件會變成 `Project.swift`。此外，你可以使用 `Workspace.swift` 嚟自定義項目點樣分組到工作區入面。你亦都可以有一個項目 `Project.swift`，其目標引用其他項目嘅目標。喺嗰啲情況下，Tuist 會生成一個包含所有項目嘅 Xcode Workspace。

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
> **Xcode 嘅語言**
>
> XcodeGen 同 Tuist 都擁抱 Xcode 嘅語言同概念。不過，Tuist 基於 Swift 嘅配置為你提供使用 Xcode 自動完成、類型檢查同驗證功能嘅便利。


## 規格模板 {#spec-templates}

YAML 作為項目配置語言嘅其中一個缺點，係佢預設唔支援跨 YAML 文件嘅重用性。這係描述項目時嘅常見需求，XcodeGen 必須透過佢哋自己專有嘅解決方案（名為 *「模板」*）嚟解決。而 Tuist 嘅重用性內置於語言本身（Swift），並透過名為 <.localized_link href="/guides/features/projects/code-sharing">項目描述助手</.localized_link> 嘅 Swift 模組實現，允許喺你所有清單文件中重用代碼。

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
