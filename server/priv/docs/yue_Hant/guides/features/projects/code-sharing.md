---
{
  "title": "共用程式碼",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "了解如何跨 manifest 檔案共用程式碼，以減少重複並確保一致性"
}
---
# 共用代碼 {#code-sharing}

當我哋用 Xcode 處理大型項目時，其中一個不便之處係佢唔允許重用項目元素（除咗透過 `.xcconfig` 檔案設定嘅編譯設定之外）。能夠重用項目定義之所以有用，原因如下：

- 減輕 **維護** 工作，因為更改可以喺一處應用，所有項目都會自動取得這些更改。
- 可以定義新項目需要遵循嘅 **規範**。
- 項目更加 **一致**，因此因不一致而導致編譯失敗嘅可能性大大降低。
- 添加新項目變得簡單，因為我哋可以重用現有邏輯。

多咗 **項目描述輔助工具** 呢個概念，Tuist 就可以喺不同清單檔案之間重用代碼。

> [!TIP]
> **Tuist 獨有優勢**
>
> 許多組織喜歡 Tuist，因為佢哋將項目描述輔助工具視為平台團隊編碼自身規範、並創建專屬項目描述語言嘅平台。例如，基於 YAML 嘅項目生成器必須開發自己專有嘅 YAML 模板解決方案，或者迫使組織基於此構建工具。


## 項目描述輔助工具 {#project-description-helpers}

項目描述輔助工具係 Swift 檔案，會被編譯成一個模組 `ProjectDescriptionHelpers`，供清單檔案導入。該模組通過收集 `Tuist/ProjectDescriptionHelpers` 目錄中嘅所有檔案進行編譯。

你可以喺清單檔案頂部添加導入語句來導入佢哋：

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` 可用於以下清單：
- `Project.swift`
- `Package.swift`（僅喺 `#TUIST` 編譯標誌下可用）
- `Workspace.swift`

## 示例 {#example}

下面嘅代碼片段展示咗我哋如何擴展 `Project` 模型以添加靜態構造函數，以及點樣從 `Project.swift` 檔案中使用佢哋：

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
> **建立規範嘅工具**
>
> 請注意，通過呢個函數，我哋定義咗關於目標名稱、Bundle Identifier 同文件夾結構嘅規範。
