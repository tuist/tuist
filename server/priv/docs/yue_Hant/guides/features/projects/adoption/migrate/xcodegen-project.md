---
{
  "title": "遷移 XcodeGen 項目",
  "titleTemplate": ":title · 遷移 · 採用 · 項目 · 功能 · 指南 · Tuist",
  "description": "了解如何將你的項目從 XcodeGen 遷移到 Tuist。"
}
---
# 遷移 XcodeGen 專案 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 係一個專案產生工具，使用 YAML 作為[設定格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)嚟定義 Xcode 專案。好多機構**採用佢，希望避開處理 Xcode 專案時經常出現嘅 Git 衝突。** 不過，頻繁嘅 Git 衝突只係機構面對嘅眾多問題之一。Xcode 令開發者要面對好多複雜細節同隱含設定，難以大規模維護同優化專案。XcodeGen 喺呢方面先天不足，因為佢只係一個產生 Xcode 專案嘅工具，並唔係專案管理器。如果你需要一個除咗產生 Xcode 專案之外仲可以幫到你嘅工具，不妨考慮下 Tuist。

> [!TIP]
> **Swift 勝過 Yaml**
>
> 好多機構都鍾意用 Tuist 作為專案產生工具，因為佢使用 Swift 作為設定格式。Swift 係開發者熟悉嘅程式語言，提供使用 Xcode 自動完成、類型檢查同驗證功能嘅便利。


以下係一啲注意事項同指引，幫你將專案由 XcodeGen 遷移到 Tuist。

## 專案產生 {#project-generation}

Tuist 同 XcodeGen 都提供 `generate` 指令，將你嘅專案聲明轉換成 Xcode 專案同工作區。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

分別在於編輯體驗。使用 Tuist，你可以執行 `tuist edit` 指令，即時產生一個 Xcode 專案俾你打開並開始工作。當你想對專案進行快速更改時，呢個特別有用。

## `project.yaml` {#projectyaml}

XcodeGen 嘅 `project.yaml` 描述檔案會變成 `Project.swift`。此外，你可以使用 `Workspace.swift` 嚟自訂專案點樣分組到工作區入面。你亦都可以有一個包含目標嘅專案 `Project.swift`，而呢啲目標會參考其他專案嘅目標。喺呢啲情況下，Tuist 會產生一個包含所有專案嘅 Xcode Workspace。

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
> XcodeGen 同 Tuist 都擁抱 Xcode 嘅語言同概念。不過，Tuist 基於 Swift 嘅設定為你提供使用 Xcode 自動完成、類型檢查同驗證功能嘅便利。


## 規格範本 {#spec-templates}

YAML 作為專案設定語言嘅其中一個缺點，係佢預設唔支援跨 YAML 檔案重用代碼。呢個係描述專案時常見嘅需求，XcodeGen 必須透過佢哋自己命名為 *「範本」* 嘅專屬解決方案嚟解決。而 Tuist 嘅重用性內建於語言本身（Swift），並透過名為 <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link> 嘅 Swift 模組實現，允許喺你所有 manifest 檔案之間重用代碼。

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
