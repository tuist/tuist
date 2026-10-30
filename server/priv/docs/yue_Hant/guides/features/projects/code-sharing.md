---
{
  "title": "程式碼共用",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何跨清單檔案共用程式碼，以減少重複並確保一致性"
}
---
# 共用程式碼 {#code-sharing}

當我們用 Xcode 處理大型專案時，其中一個不便之處是除了透過 `.xcconfig` 檔案設定建構選項外，無法重用專案的其他元素。能夠重用專案定義有以下好處：

- 簡化**維護**，因為只需在一處套用變更，所有專案都會自動同步。
- 可以定義新專案可遵循的**規範**。
- 專案更加**一致**，因此因不一致而導致建構失敗的機會大幅降低。
- 新增專案變得輕鬆，因為可以重用既有邏輯。

得益於**project description helpers**的概念，Tuist 讓你在多個 manifest 檔案之間重用程式碼。

> [!TIP]
> **Tuist 的獨特優勢**
>
> 許多機構喜歡 Tuist，因為他們將 project description helpers 視為平台團隊編碼自身規範、並建立描述專案的專屬語言的平台。例如，基於 YAML 的專案產生器必須自行設計專有的 YAML 範本方案，或迫使機構在其上建構工具。


## Project description helpers {#project-description-helpers}

Project description helpers 是會被編譯成模組 `ProjectDescriptionHelpers` 的 Swift 檔案，manifest 檔案可以匯入該模組。系統會收集 `Tuist/ProjectDescriptionHelpers` 目錄中的所有檔案來編譯此模組。

你可以在 manifest 檔案頂部加入 import 敘述來匯入它們：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` 可在以下 manifest 中使用：
- `Project.swift`
- `Package.swift`（僅在啟用 `#TUIST` 編譯器旗標時可用）
- `Workspace.swift`

## 範例 {#example}

以下程式碼片段展示如何擴充 `Project` 模型以加入靜態建構子，以及如何在 `Project.swift` 檔案中使用它們：

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

> [!TIP]
> **建立規範的工具**
>
> 留意我們如何透過函式定義關於 target 名稱、bundle identifier 及資料夾結構的規範。
