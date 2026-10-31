---
{
  "title": "元數據標籤",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何使用目標元數據標籤來組織並專注於專案的特定部分"
}
---
# 中繼資料標籤 {#metadata-tags}

隨著專案規模與複雜度增加，一次性處理整個程式碼庫會變得更低效。Tuist 提供**中繼資料標籤**，讓你可以將 target 組織成邏輯群組，並在開發期間專注於專案的特定部分。

## 甚麼是中繼資料標籤？ {#what-are-metadata-tags}

中繼資料標籤是可以附加到專案中 target 的字串標籤。它們作為標記，讓你可以：

- **將相關 target 分組** - 為屬於同一功能、團隊或架構層的 target 加上標籤
- **聚焦工作區** - 產生只包含具有特定標籤之 target 的專案
- **最佳化工作流程** - 專注於特定功能，而無需載入程式碼庫中不相關的部分
- **選擇保留為原始碼的 target** - 在快取時選擇你想保留為原始碼的 target 群組

標籤是透過 target 上的 `metadata` 屬性定義，並以字串陣列形式儲存。

## 定義中繼資料標籤 {#defining-metadata-tags}

你可以在專案清單中為任何 target 加入標籤：

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

## 聚焦已加標籤的 target {#focusing-on-tagged-targets}

為 target 加上標籤後，你可以使用 `tuist generate` 指令來建立一個聚焦專案，其中只包含特定的 target：

### 按標籤聚焦

使用 `tag:` 前綴來產生包含所有符合特定標籤之 target 的專案：

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### 按名稱聚焦

你也可以按名稱聚焦於特定 target：

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### 聚焦如何運作

當你聚焦於 target 時：

1. **包含的 target** - 符合你查詢條件的 target 會被包含在產生的專案中
2. **相依性** - 聚焦 target 的所有相依性會自動被包含
3. **測試 target** - 聚焦 target 對應的測試 target 會被包含
4. **排除** - 所有其他 target 會從工作區中排除

這表示你會獲得一個更小、更易於管理的工作區，其中只包含開發功能所需的內容。

## 標籤命名慣例 {#tag-naming-conventions}

雖然你可以使用任何字串作為標籤，但遵循一致的命名慣例有助於保持標籤井然有序：

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

使用如 `feature:`、`team:` 或 `layer:` 等前綴，可以更容易理解每個標籤的用途並避免命名衝突。

## 系統標籤 {#system-tags}

Tuist 使用 `tuist:` 前綴來標示系統管理的標籤。這些標籤由 Tuist 自動套用，並可在快取設定檔中使用，以針對特定類型的產生內容。

### 可用的系統標籤

| 標籤 | 說明 |
| --- | --- |
| `tuist:synthesized` | 套用到 Tuist 為靜態程式庫和靜態框架中的資源處理所建立的合成 bundle target。這些 bundle 出於歷史原因而存在，以提供資源存取器 API。 |

### 在快取設定檔中使用系統標籤

你可以在快取設定檔中使用系統標籤，以包含或排除合成的 target：

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

> [!TIP]
> **合成 Bundle 會繼承父項標籤**
>
> 合成 bundle target 除了接收 `tuist:synthesized` 標籤外，還會繼承其父項 target 的所有標籤。這表示如果你為靜態程式庫加上 `feature:auth` 標籤，其合成的資源 bundle 將同時具有 `feature:auth` 和 `tuist:synthesized` 標籤。


## 搭配專案描述輔助工具使用標籤 {#using-tags-with-helpers}

你可以利用<.localized_link href="/guides/features/projects/code-sharing">專案描述輔助工具</.localized_link>，將標籤應用方式標準化：

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

然後在你的清單中使用它：

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

## 使用元數據標籤的好處 {#benefits}

### 提升開發體驗

透過聚焦於專案的特定部分，你可以：

- **縮小 Xcode 專案規模** - 處理較小的專案，開啟和導覽速度更快
- **加快建構速度** - 只建構目前工作所需的內容
- **提升專注度** - 避免被不相關的程式碼干擾
- **最佳化索引** - Xcode 索引的程式碼較少，讓自動完成功能更快

### 更好的專案組織

標籤提供了一種靈活的方式來組織你的程式碼庫：

- **多個維度** - 按功能、團隊、層級、平台或任何其他維度為 target 加上標籤
- **無需結構變更** - 在不改變目錄結構的情況下新增組織架構
- **跨領域關注點** - 單一 target 可以屬於多個邏輯群組

### 與快取整合

元數據標籤可與<.localized_link href="/guides/features/cache">Tuist 的快取功能</.localized_link>無縫協作：

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## 最佳實踐 {#best-practices}

1. **從簡單開始** - 從單一標籤維度（例如功能）開始，並按需擴展
2. **保持一致性** - 在所有清單中使用相同的命名慣例
3. **記錄你的標籤** - 在專案文件中維護可用標籤及其含義的清單
4. **使用輔助工具** - 利用專案描述輔助工具來標準化標籤應用
5. **定期檢視** - 隨著專案演進，檢視並更新你的標籤策略

## 相關功能 {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">程式碼共用</.localized_link> - 使用專案描述輔助工具來標準化標籤用法
- <.localized_link href="/guides/features/cache">快取</.localized_link> - 將標籤與快取結合，以獲得最佳建構效能
- <.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link> - 僅針對已變更的 target 執行測試
