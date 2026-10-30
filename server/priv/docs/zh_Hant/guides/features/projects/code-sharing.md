---
{
  "title": "程式碼共用",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在清單檔案之間共用程式碼，以減少重複並確保一致性"
}
---
# 程式碼共用 {#code-sharing}

在大型專案中使用 Xcode 時，其中一個不便之處在於它不允許重複使用專案元素，除了透過 `.xcconfig` 檔案的建置設定。能夠重複使用專案定義有下列好處：

- 簡化**維護**，因為變更只需在一處套用，所有專案就會自動取得這些變更。
- 可定義新專案能遵循的**規範**。
- 專案更具**一致性**，因此因不一致而導致建置失敗的可能性大幅降低。
- 新增專案變得輕鬆，因為我們可以重複使用既有邏輯。

得益於**專案描述輔助工具**的概念，Tuist 允許在不同清單檔案間重複使用程式碼。

> [!TIP]
> **Tuist 的獨特優勢**
>
> 許多組織喜歡 Tuist，因為他們將專案描述輔助工具視為平台團隊編碼自身規範並打造專屬專案描述語言的平台。例如，基於 YAML 的專案產生器必須提出自己的 YAML 專有範本解決方案，或迫使組織在其基礎上建構工具。


## 專案描述輔助工具 {#project-description-helpers}

專案描述輔助工具是會被編譯成模組 `ProjectDescriptionHelpers` 的 Swift 檔案，清單檔案可以匯入該模組。該模組會收集 `Tuist/ProjectDescriptionHelpers` 目錄中的所有檔案進行編譯。

你可以在檔案頂端加入 import 敘述，將其匯入清單檔案：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` 可在下列清單中使用：
- `Project.swift`
- `Package.swift`（僅在 `#TUIST` 編譯器旗標後可用）
- `Workspace.swift`

## 範例 {#example}

以下程式碼片段展示我們如何擴充 `Project` 模型以加入靜態建構子，以及如何在 `Project.swift` 檔案中使用它們：

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
