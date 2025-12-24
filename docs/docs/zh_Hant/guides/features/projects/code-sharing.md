---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# 代碼分享{#code-sharing}

當我們在大型專案中使用 Xcode 時，其中一個不便之處就是它不允許透過`.xcconfig`
檔重複使用專案中除建立設定以外的元素。能夠重複使用專案定義非常有用，原因如下：

- 它可以簡化**維護** ，因為變更可以在一個地方套用，而且所有專案都會自動取得變更。
- 它可以定義**慣例** ，讓新專案符合這些慣例。
- 專案的一致性更高**** ，因此因不一致而造成建置破損的可能性大幅降低。
- 新增專案變得很容易，因為我們可以重複使用現有的邏輯。

透過**專案描述輔助工具** 的概念，Tuist 可以在不同的清單檔案中重複使用程式碼。

::: tip A TUIST UNIQUE ASSET
<!-- -->
許多組織喜歡 Tuist，因為他們在專案描述輔助工具中看到了一個平台，讓平台團隊可以編纂他們自己的慣例，並提出他們自己的專案描述語言。例如，基於 YAML
的專案產生器必須提出他們自己的基於 YAML 的專利模板解決方案，或強迫組織建立他們的工具。
<!-- -->
:::

## 專案描述協助{#project-description-helpers}

專案描述輔助程式是 Swift 檔案，會被編譯成一個模組，`ProjectDescriptionHelpers`
，而艙單檔案可以匯入這個模組。該模組是透過收集`Tuist/ProjectDescriptionHelpers` 目錄中的所有檔案來編譯。

您可以在檔案頂端加入匯入語句，將它們匯入您的艙單檔案：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` 可在下列艙單中找到：
- `Project.swift`
- `Package.swift` (僅在`#TUIST` 編譯器旗號之後)
- `工作區.swift`

## 範例{#example}

以下片段包含一個範例，說明我們如何擴充`Project` 模型，以加入靜態構造程式，以及如何從`Project.swift` 檔案使用這些構造程式：

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
請注意我們如何透過函式定義目標名稱、bundle 識別符和資料夾結構的慣例。
<!-- -->
:::
