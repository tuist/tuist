---
{
  "title": "程式碼共用",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在資訊清單檔案之間共用程式碼，以減少重複並確保一致性"
}
---
# 程式碼共用 {#code-sharing}

在使用 Xcode 處理大型專案時，其中一個不便之處在於除了透過 `.xcconfig` 檔案設定建置參數外，無法重複使用專案中的其他元素。能夠重複使用專案定義具有以下優點：

- 簡化**維護**作業，因為只需在一處套用變更，所有專案便會自動同步更新。
- 可定義新專案遵循的**規範**。
- 提升專案間的**一致性**，大幅降低因不一致而導致建置失敗的機率。
- 新增專案變得更加輕鬆，因為可以直接重複使用既有邏輯。

在 Tuist 中，得益於**專案描述輔助工具**的概念，我們可以在各個資訊清單檔案之間重複使用程式碼。

> [!TIP]
> **Tuist 的獨特優勢**
>
> 許多組織採用 Tuist，是因為他們將專案描述輔助工具視為平台團隊編碼自身規範、並發展出專屬專案描述語言的平台。例如，基於 YAML 的專案產生器必須自行開發專屬的 YAML 樣板解決方案，或迫使組織在其基礎上建構工具。


## 專案描述輔助工具 {#project-description-helpers}

專案描述輔助工具是會被編譯為模組 `ProjectDescriptionHelpers` 的 Swift 檔案，資訊清單檔案可以匯入此模組。該模組會收集 `Tuist/ProjectDescriptionHelpers` 目錄中的所有檔案進行編譯。

您可以在資訊清單檔案頂部加入 import 陳述式來匯入它們：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` 可在以下資訊清單中使用：
- `Project.swift`
- `Package.swift`（僅在啟用 `#TUIST` 編譯器旗標時可用）
- `Workspace.swift`

## 範例 {#example}

以下程式碼片段示範如何擴充 `Project` 模型以新增靜態建構子，以及如何在 `Project.swift` 檔案中使用它們：

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
> 請注意，我們透過函式定義了關於目標名稱、Bundle Identifier 與資料夾結構的規範。
