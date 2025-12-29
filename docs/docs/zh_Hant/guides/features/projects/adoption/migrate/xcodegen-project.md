---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# 遷移 XcodeGen 專案{#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一個專案產生工具，使用 YAML 作為
[設定格式](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)，來定義
Xcode 專案。許多組織**採用它，試圖擺脫在處理 Xcode 專案時經常發生的 Git 衝突。** 然而，頻繁的 Git
衝突只是組織所遇到的眾多問題之一。Xcode 為開發人員提供了大量錯綜複雜的隱含配置，這使得在規模上維護和優化專案變得困難。XcodeGen
在設計上有不足之處，因為它只是一個產生 Xcode 專案的工具，而不是專案管理員。如果您需要一個除了生成 Xcode 專案之外還能幫助您的工具，您可能需要考慮
Tuist。

::: tip SWIFT OVER YAML
<!-- -->
許多組織也偏好使用 Tuist 作為專案產生工具，因為它使用 Swift 作為組態格式。Swift 是開發人員熟悉的程式語言，可讓他們方便地使用 Xcode
的自動完成、類型檢查和驗證功能。
<!-- -->
:::

以下是一些注意事項和指引，可協助您將專案從 XcodeGen 移轉到 Tuist。

## 專案產生{#project-generation}

Tuist 和 XcodeGen 都提供了`generate` 指令，可將您的專案宣告轉換成 Xcode 專案和工作區。

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

不同之處在於編輯體驗。使用 Tuist，您可以執行`tuist edit` 指令，它會立即產生一個 Xcode
專案，您可以開啟並開始工作。當您想要快速變更專案時，這個功能特別有用。

## `project.yaml` {#projectyaml}

XcodeGen 的`project.yaml` 描述檔會變成`Project.swift` 。此外，您可以有`Workspace.swift`
，以此自訂專案在工作區中的分組方式。您也可以讓專案`Project.swift` 的目標參考其他專案的目標。在這些情況下，Tuist 會產生一個包含所有專案的
Xcode 工作區。

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
XcodeGen 和 Tuist 都接受 Xcode 的語言和概念。然而，Tuist 基於 Swift 的配置可讓您方便地使用 Xcode
的自動完成、類型檢查和驗證功能。
<!-- -->
:::

## 規格模板{#spec-templates}

YAML 作為專案設定語言的缺點之一，就是它不支援 YAML 檔案之間的重複使用。這是描述專案時的一個普遍需求，XcodeGen
不得不使用他們自己專屬的解決方案來解決這個問題，該解決方案命名為*"templates"* 。Tuist 的重複使用功能內建於 Swift
語言本身，並透過一個名為
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink> 的 Swift 模組，讓程式碼能夠在所有的清單檔案中重複使用。

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
