---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# 元資料標籤{#metadata-tags}

隨著專案規模與複雜度的增加，一次處理整個程式碼庫可能會變得沒有效率。Tuist 提供**metadata 標籤**
，作為一種將目標組織為邏輯群組的方式，並在開發過程中專注於專案的特定部分。

## 什麼是元資料標籤？{#what-are-metadata-tags}

Metadata 標籤是您可以附加到專案中目標的字串標籤。它們作為標記，可讓您

- **群組相關目標** - 標記屬於相同功能、團隊或架構層的目標
- **集中您的工作區** - 產生僅包含特定標籤的目標的專案
- **優化您的工作流程** - 在特定功能上工作，而無需載入程式碼庫中不相關的部分
- **選擇要保留為來源的目標** - 選擇要在快取時將哪組目標保留為來源

標籤是使用目標上的`metadata` 屬性定義，並儲存為字串陣列。

## 定義元資料標籤{#defining-metadata-tags}

您可以為專案清單中的任何目標新增標籤：

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

## 專注於標記的目標{#focusing-on-tagged-targets}

一旦您標記了目標，就可以使用`tuist generate` 指令建立只包含特定目標的專案：

### 依標籤聚焦

使用`tag:` 前綴，可產生包含所有符合特定標籤的目標的專案：

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 按名稱聚焦

您也可以依名稱針對特定目標：

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 焦點如何運作

當您專注於目標時：

1. **包含的目標** - 在產生的專案中包含符合您查詢的目標
2. **相依性** - 自動包含重點目標的所有相依性
3. **測試目標** - 包括重點目標的測試目標
4. **排除** - 工作區排除所有其他目標

這表示您可以獲得更小、更容易管理的工作空間，其中只包含您在功能上工作所需的內容。

## 標籤命名慣例{#tag-naming-conventions}

雖然您可以使用任何字串作為標籤，但遵循一致的命名慣例有助於保持您的標籤井井有條：

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

使用前綴，例如`feature:`,`team:`, 或`layer:` ，可以讓您更容易了解每個標籤的目的，並避免命名衝突。

## 系統標籤{#system-tags}

Tuist 對系統管理的標籤使用`tuist:` 前綴。這些標籤由 Tuist 自動套用，並可在快取設定檔中使用，以針對特定類型的已產生內容。

### 可用的系統標記

| 標籤         | 說明                                                                          |
| ---------- | --------------------------------------------------------------------------- |
| `tuist:合成` | 應用於 Tuist 在靜態函式庫和靜態框架中為資源處理而建立的合成 bundle 目標。這些 bundle 存在的歷史原因是為了提供資源存取 API。 |

### 使用快取設定檔的系統標記

您可以在快取設定檔中使用系統標籤來包含或排除合成的目標：

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
合成資源包目標除了接收`tuist:synthesized` 標籤外，還會繼承其父目標的所有標籤。這表示如果您使用`feature:auth`
標籤靜態函式庫，其合成的資源包將同時具有`feature:auth` 和`tuist:synthesized` 標籤。
<!-- -->
:::

## 使用專案描述輔助標籤{#using-tags-with-helpers}

您可以利用 <LocalizedLink href="/guides/features/projects/code-sharing">
專案描述輔助工具</LocalizedLink>，將標籤在專案中的應用方式標準化：

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

然後在您的艙單中使用它：

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

## 使用元數據標籤的好處{#benefits}

### 改善開發體驗

透過專注於專案的特定部分，您可以

- **減少 Xcode 專案大小** - 使用較小的專案工作，開啟和瀏覽速度更快
- **加速建置** - 只建置目前工作所需的內容
- **提高專注力** - 避免不相關的程式碼分散您的注意力
- **最佳化索引** - Xcode 索引較少的程式碼，使自動完成的速度更快

### 更好的專案組織

標籤提供靈活的方式來組織您的程式碼庫：

- **多重維度** - 依功能、團隊、層級、平台或任何其他維度標記目標
- **不變更結構** - 新增組織結構，但不變更目錄配置
- **跨領域關注** - 一個目標可以屬於多個邏輯群組

### 與快取整合

Metadata 標籤可與 <LocalizedLink href="/guides/features/cache">Tuist
的快取功能</LocalizedLink>無縫配合：

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## 最佳實踐{#best-practices}

1. **從簡單的** - 從單一標籤維度 (例如特徵) 開始，然後視需要擴展
2. **保持一致** - 在所有艙單中使用相同的命名慣例
3. **記錄您的標籤** - 在專案文件中記錄可用的標籤清單及其含義
4. **使用輔助工具** - 利用專案描述輔助工具來標準化標籤應用
5. **定期檢閱** - 隨著專案的演進，檢閱並更新您的標籤策略

## 相關功能{#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">程式碼分享{1｝-
  使用專案描述輔助工具來標準化標籤用法
- <LocalizedLink href="/guides/features/cache">快取{1｝- 將標籤與快取結合，以獲得最佳的建立效能
- <LocalizedLink href="/guides/features/selective-testing">選擇性測試{1｝-
  僅針對變更的目標執行測試
