---
{
  "title": "遷移 XcodeGen 項目",
  "titleTemplate": ":title · 遷移 · 採用 · 項目 · 功能 · 指南 · Tuist",
  "description": "了解如何將你的項目從 XcodeGen 遷移至 Tuist。"
}
---
# 遷移 XcodeGen 項目 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一個項目生成工具，使用 YAML 作為[配置格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)來定義 Xcode 項目。許多組織**採用它是為了避免在使用 Xcode 項目時頻繁出現的 Git 衝突。** 然而，頻繁的 Git 衝突只是組織面臨的眾多問題之一。Xcode 讓開發者面對許多複雜性和隱式配置，這使得在大規模下維護和優化項目變得困難。XcodeGen 在這方面有所不足，因為它是一個生成 Xcode 項目的工具，而不是項目管理器。如果你需要一個不僅能生成 Xcode 項目的工具，你可以考慮 Tuist。你不必遷移才能使用 Tuist：[XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen) 解釋了哪些功能（例如 Xcode 緩存和構建洞察）可以與 XcodeGen 項目一起工作，以及何時值得遷移。

> [!TIP]
> **Swift 優於 YAML**
>
> 許多組織也 prefer Tuist 作為項目生成工具，因為它使用 Swift 作為配置格式。Swift 是一種開發者熟悉的編程語言，並且提供了使用 Xcode 自動完成、類型檢查和驗證功能的便利。


以下是一些考慮因素和指南，幫助你將項目從 XcodeGen 遷移到 Tuist。

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

區別在於編輯體驗。使用 Tuist，你可以運行 `tuist edit` 命令，即時生成一個 Xcode 項目，你可以打開並開始工作。這在你想要快速更改項目時特別有用。

## `project.yaml` {#projectyaml}

XcodeGen 的 `project.yaml` 描述文件變成了 `Project.swift`。此外，你可以有 `Workspace.swift` 來自定義如何將項目分組到工作區中。你也可以有一個項目 `Project.swift`，其中包含引用其他項目目標的目標。在這些情況下，Tuist 會生成一個包含所有項目的 Xcode Workspace。

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
> XcodeGen 和 Tuist 都採用了 Xcode 的語言和概念。然而，Tuist 的基於 Swift 的配置為你提供了使用 Xcode 自動完成、類型檢查和驗證功能的便利。


## 規範模板 {#spec-templates}

YAML 作為專案設定語言其中一個缺點，係預設唔支援跨 YAML 檔案重用。描述專案時經常需要呢項功能，XcodeGen 唯有用自己專屬嘅方案 *「templates」* 去解決。Tuist 嘅重用能力直接內建於 Swift 語言本身，並透過名為 <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link> 嘅 Swift 模組實現，讓你可以喺所有 manifest 檔案之間重用代碼。

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
