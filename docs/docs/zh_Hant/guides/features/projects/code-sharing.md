---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# 程式碼共享{#code-sharing}

在大型專案中使用 Xcode 時，其不便之處在於無法透過 ``.xcconfig` 與 `` `
檔案重複使用專案元素（建置設定除外）。重複使用專案定義具有以下實用價值：

- 這能簡化**的維護工作** ，因為變更只需在單一位置進行，所有專案便會自動獲得更新。
- 這使得定義**規範** 成為可能，新專案可遵循此規範。
- 專案採用更一致的格式規範（**），因此因格式不一致導致建置失敗的機率大幅降低（** ）。
- 新增專案變得輕而易舉，因為我們能重複使用現有邏輯。

Tuist 透過「專案描述輔助函式」概念實現跨清單檔案的程式碼重用功能，詳見：**project-description-helpers**

::: tip A TUIST UNIQUE ASSET
<!-- -->
許多組織青睞 Tuist，因為他們在專案描述輔助工具中看見了平台團隊制定自身規範、發展專屬專案描述語言的契機。舉例而言，基於 YAML
的專案生成器必須開發專屬的 YAML 模板解決方案，否則將迫使組織依賴其工具進行建置。
<!-- -->
:::

## 專案說明輔助工具{#project-description-helpers}

專案描述輔助程式是 Swift 檔案，編譯後會形成模組`ProjectDescriptionHelpers`
，供清單檔案匯入。該模組透過彙整`Tuist/ProjectDescriptionHelpers` 目錄下的所有檔案進行編譯。

您可在檔案頂端加入 import 陳述式，將其匯入您的清單檔案：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` 可於下列清單中取得：
- `Project.swift`
- `Package.swift` (僅在啟用`#TUIST` 編譯器標記時生效)
- `工作區.swift`

## 範例{#example}

以下程式碼片段示範如何擴展`專案` 的模型以新增靜態建構函式，以及如何從`Project.swift` 檔案中使用這些函式：

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

::: tip A TOOL TO ESTABLISH CONVENTIONS
<!-- -->
請注意，我們透過此函式定義了目標名稱、套件識別碼及資料夾結構的規範。
<!-- -->
:::
