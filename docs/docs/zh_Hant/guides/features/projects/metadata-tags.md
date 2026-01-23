---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# 元數據標籤{#metadata-tags}

隨著專案規模與複雜度增加，同時處理整個程式碼庫可能變得低效。Tuist提供**元數據標籤** ，可將目標組織成邏輯群組，讓您在開發過程中專注於專案的特定部分。

## 何謂元數據標籤？{#what-are-metadata-tags}

元資料標籤是可附加於專案目標的字串標籤。它們作為標記，可讓您：

- **將相關目標分組** - 標記屬於相同功能、團隊或架構層級的目標
- **聚焦您的工作區** - 僅生成包含特定標籤目標的專案
- **優化您的工作流程** - 專注開發特定功能，無需載入程式碼庫中無關的模組
- **選擇要保留為來源的目標** - 選擇您希望在快取時保留為來源的目標群組

標籤透過目標的`元數據` 屬性定義，並以字串陣列形式儲存。

## 定義元資料標籤{#defining-metadata-tags}

您可在專案清單中的任何目標添加標籤：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## 聚焦於標記目標{#focusing-on-tagged-targets}

標記目標後，可使用 ``` 指令生成 `` ` 命令，建立僅包含特定目標的聚焦專案：

### 依標籤聚焦

`使用標籤：使用 `` ` 前綴，可建立所有目標皆符合特定標籤的專案：

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 按名稱聚焦

您亦可透過名稱鎖定特定目標：

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 焦點運作原理

當你聚焦於目標時：

1. **包含目標** - 與您的查詢相符的目標已包含在生成的專案中
2. **依賴項** - 所有聚焦目標的依賴項皆會自動包含
3. **測試目標** - 包含聚焦目標的測試目標
4. **排除目標：** - 所有其他目標皆排除於工作區之外

這意味著您將獲得更精簡、更易於管理的作業空間，其中僅包含開發功能所需的必要元素。

## 標籤命名規範{#tag-naming-conventions}

雖然可使用任意字串作為標籤，但遵循一致的命名規範有助於保持標籤條理分明：

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

使用前綴如：`（功能）:`,`（團隊）:`, 或`（圖層）:` ，有助於理解各標籤用途並避免命名衝突。

## 系統標籤{#system-tags}

Tuist 使用`tuist:` 前綴作為系統管理的標籤。這些標籤由 Tuist 自動套用，並可於快取設定檔中使用，以鎖定特定類型的生成內容。

### 可用系統標籤

| 標籤                  | 說明                                                             |
| ------------------- | -------------------------------------------------------------- |
| `tuist:synthesized` | 適用於 Tuist 為靜態函式庫與靜態框架資源處理所建立的合成封裝目標。此類封裝因歷史緣由而存在，旨在提供資源存取 API。 |

### 使用系統標籤與快取設定檔

您可在快取設定檔中使用系統標籤來包含或排除合成目標：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

::: tip SYNTHESIZED BUNDLES INHERIT PARENT TAGS
<!-- -->
合成資源包目標除繼承父目標的所有標籤外，還會附加`tuist:synthesized` 標籤。這意味著若您為靜態庫標記`feature:auth`
，其合成資源包將同時具備`feature:auth` 標籤與`tuist:synthesized` 標籤。
<!-- -->
:::

## 使用專案描述輔助標籤{#using-tags-with-helpers}

您可運用
<LocalizedLink href="/guides/features/projects/code-sharing">專案描述輔助工具</LocalizedLink>
統一專案中標籤的應用方式：

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

然後在您的清單檔案中使用它：

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## 使用元數據標籤的優勢{#benefits}

### 提升開發體驗

透過聚焦專案的特定部分，您可實現：

- **縮小 Xcode 專案體積** - 使用體積更小、開啟與導覽更迅速的專案
- **加速建置** - 僅為當前工作所需進行建置
- **提升專注度** - 避免與主題無關的程式碼造成干擾
- **優化索引功能** - Xcode 索引較少程式碼，使自動完成功能更快速

### 更完善的專案組織

標籤提供了一種靈活的方式來組織您的程式碼庫：

- **多重維度** - 依功能、團隊、圖層、平台或其他維度標記目標
- **不變更結構** - 添加組織架構時不變更目錄佈局
- **橫切關注點** - 單一目標可隸屬於多個邏輯群組

### 與快取系統的整合

元資料標籤能與 <LocalizedLink href="/guides/features/cache">Tuist
的快取功能</LocalizedLink>無縫整合：

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## 最佳實踐{#best-practices}

1. **從簡單開始** - 先從單一標註維度著手（例如：特色），再視需求擴展
2. **保持一致性** - 所有清單檔均採用相同命名規範
3. **標記文件化** - 在專案文件中列出可用標記及其含義
4. **使用輔助工具** - 善用專案說明輔助工具以標準化標籤應用
5. **定期檢視** - 隨著專案進展，請定期檢視並更新標籤策略

## 相關功能{#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">程式碼共享</LocalizedLink>
  - 使用專案描述輔助工具以標準化標籤使用
- <LocalizedLink href="/guides/features/cache">快取</LocalizedLink> -
  結合標籤與快取機制以實現最佳建置效能
- <LocalizedLink href="/guides/features/selective-testing">選擇性測試</LocalizedLink>
  - 僅針對變更目標執行測試
