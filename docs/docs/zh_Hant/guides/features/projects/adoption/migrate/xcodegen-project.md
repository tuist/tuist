---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# 遷移 XcodeGen 專案{#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一款專案生成工具，它採用 YAML 作為
[配置格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
來定義 Xcode 專案。許多組織**採用了它，試圖擺脫在處理 Xcode 專案時經常發生的 Git 衝突。** 然而，頻繁的 Git
衝突僅是組織所面臨的眾多問題之一。Xcode 讓開發者暴露於許多複雜細節與隱含設定之中，使得專案在規模化時難以維護與優化。 XcodeGen
因設計上的限制而在這方面有所欠缺，因為它僅是一款用於生成 Xcode 專案的工具，而非專案管理工具。若您需要一款能提供超越 Xcode
專案生成功能的工具，不妨考慮 Tuist。

::: tip SWIFT OVER YAML
<!-- -->
許多組織也偏好將 Tuist 作為專案生成工具，因為它採用 Swift 作為配置格式。Swift 是一種開發人員熟悉的程式語言，能讓他們輕鬆運用 Xcode
的自動完成、類型檢查和驗證功能。
<!-- -->
:::

以下是一些注意事項與指引，可協助您將專案從 XcodeGen 遷移至 Tuist。

## 專案生成{#project-generation}

Tuist 和 XcodeGen 均提供「`generate` 」指令，可將您的專案宣告轉為 Xcode 專案和工作區。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

差異在於編輯體驗。使用 Tuist 時，您可以執行 ``tuist edit` ` 指令，系統會即時生成一個 Xcode
專案，您可直接開啟並開始進行開發。這在您需要快速修改專案時特別有用。

## `project.yaml` {#projectyaml}

XcodeGen 的`project.yaml` 描述檔將轉為`Project.swift` 。此外，您可以使用`Workspace.swift`
來自訂專案在工作區中的分組方式。您也可以建立一個專案`Project.swift` ，其目標會引用其他專案中的目標。在這些情況下，Tuist
會生成一個包含所有專案的 Xcode 工作區。

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

::: tip XCODE'S LANGUAGE
<!-- -->
XcodeGen 和 Tuist 皆採用 Xcode 的語言與概念。然而，Tuist 基於 Swift 的設定方式，能讓您輕鬆使用 Xcode
的自動完成、類型檢查及驗證功能。
<!-- -->
:::

## 規格範本{#spec-templates}

作為專案配置語言，YAML 的缺點之一在於它預設不支援跨 YAML 檔案的重複使用。 這在描述專案時是常見的需求，XcodeGen 曾透過其專有解決方案「*
範本」* 來解決此問題。而在 Tuist 中，可重用性已內建於 Swift 語言本身，並透過名為
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink> 的 Swift 模組實現，該模組允許在所有 manifests 檔案中重用程式碼。

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
