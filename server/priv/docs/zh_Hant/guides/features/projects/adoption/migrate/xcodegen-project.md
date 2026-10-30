---
{
  "title": "遷移 XcodeGen 專案",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何將專案從 XcodeGen 遷移至 Tuist。"
}
---
# 遷移 XcodeGen 專案 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一個專案產生工具，使用 YAML 作為[設定格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)來定義 Xcode 專案。許多組織**採用它是為了避免在使用 Xcode 專案時頻繁發生的 Git 衝突。** 然而，頻繁的 Git 衝突只是組織面臨的眾多問題之一。Xcode 讓開發者面對許多複雜性與隱含設定，使得在大規模下維護和最佳化專案變得困難。XcodeGen 在這方面先天不足，因為它是一個產生 Xcode 專案的工具，而非專案管理器。如果你需要一個能超越產生 Xcode 專案並提供更多協助的工具，你可以考慮 Tuist。

> [!TIP]
> **Swift 勝過 YAML**
>
> 許多組織也偏好將 Tuist 作為專案產生工具，因為它使用 Swift 作為設定格式。Swift 是開發者熟悉的程式語言，並提供使用 Xcode 自動完成、型別檢查與驗證功能的便利性。


以下提供一些考量與指南，協助你將專案從 XcodeGen 遷移至 Tuist。

## 專案產生 {#project-generation}

Tuist 與 XcodeGen 都提供 `generate` 指令，可將你的專案宣告轉換為 Xcode 專案與工作區。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

差異在於編輯體驗。使用 Tuist 時，你可以執行 `tuist edit` 指令，即時產生一個可開啟並開始工作的 Xcode 專案。當你需要對專案進行快速變更時，這特別有用。

## `project.yaml` {#projectyaml}

XcodeGen 的 `project.yaml` 描述檔案會變成 `Project.swift`。此外，你可以使用 `Workspace.swift` 來自訂專案在工作區中的分組方式。你也可以建立一個包含目標的專案 `Project.swift`，這些目標會參考其他專案中的目標。在這種情況下，Tuist 會產生一個包含所有專案的 Xcode 工作區。

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
> XcodeGen 與 Tuist 都採用 Xcode 的語言與概念。然而，Tuist 基於 Swift 的設定提供了使用 Xcode 自動完成、型別檢查與驗證功能的便利性。


## 規格範本 {#spec-templates}

YAML 作為專案設定語言的缺點之一，是預設不支援跨 YAML 檔案的可重用性。這在描述專案時是常見需求，XcodeGen 必須透過其專有解決方案「*範本*」來解決。Tuist 的可重用性則內建於語言本身（Swift），並透過名為 <.localized_link href="/guides/features/projects/code-sharing">專案描述輔助工具</.localized_link> 的 Swift 模組實現，讓你可以在所有清單檔案中重複使用程式碼。

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
