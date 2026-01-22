---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# 遷移 XcodeGen 專案{#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一款採用 YAML
作為[配置格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)來定義
Xcode 專案的生成工具。許多組織**採用它，試圖擺脫處理 Xcode 專案時頻繁發生的 Git 衝突。** 然而，頻繁的 Git
衝突僅是組織面臨眾多問題之一。Xcode 向開發者暴露了大量複雜細節與隱含配置，使得大規模專案的維護與優化變得困難。 XcodeGen
因設計限制而無法解決此問題，因為它僅是生成 Xcode 專案的工具，而非專案管理系統。若您需要超越專案生成功能的解決方案，Tuist 或許是值得考慮的選擇。

::: tip SWIFT OVER YAML
<!-- -->
許多組織也偏好將 Tuist 作為專案生成工具，因為它採用 Swift 作為設定格式。Swift 是開發者熟悉的程式語言，能讓他們便捷地使用 Xcode
的自動完成、類型檢查與驗證功能。
<!-- -->
:::

以下提供若干考量要點與指引，協助您將專案從 XcodeGen 遷移至 Tuist。

## 專案生成{#project-generation}

Tuist 與 XcodeGen 皆提供 ``` 生成 `` ` 的指令，可將專案聲明轉換為 Xcode 專案與工作區。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

差異在於編輯體驗。使用 Tuist 時，您可執行 ``` tuist edit `` ` 指令，該指令會即時生成 Xcode
專案供您開啟並開始工作。此功能在需要快速修改專案時尤為實用。

## `project.yaml` {#projectyaml}

XcodeGen 的`project.yaml` 描述檔將轉為`Project.swift` 。此外，您可透過`Workspace.swift`
自訂專案在工作區中的分組方式。亦可建立專案`Project.swift` 其目標可引用其他專案的目標。此類情況下，Tuist 將生成包含所有專案的 Xcode
工作區。

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
XcodeGen 與 Tuist 皆採用 Xcode 的語言與概念。然而 Tuist 基於 Swift 的設定方式，讓您能便捷地使用 Xcode
的自動完成、類型檢查與驗證功能。
<!-- -->
:::

## 規格範本{#spec-templates}

YAML 作為專案配置語言的缺點之一，在於其預設不支援跨 YAML 檔案的重複使用性。 在描述專案時，此需求相當常見，XcodeGen 為此開發了名為*
「範本」* 的專屬解決方案。Tuist 則將可重複使用性直接內建於 Swift
語言本身，並透過名為<LocalizedLink href="/guides/features/projects/code-sharing">專案描述輔助工具</LocalizedLink>的
Swift 模組實現，使您能在所有清單檔案中重複使用程式碼。

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
