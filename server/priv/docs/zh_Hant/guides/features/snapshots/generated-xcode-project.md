---
{
  "title": "產生的 Xcode 專案",
  "titleTemplate": ":title · 快照 · 功能 · 指南 · Tuist",
  "description": "為 Tuist 產生之專案的每個 SwiftUI 預覽建立快照，並在 Tuist 中檢視變更。"
}
---
# 產生的 Xcode 專案快照 {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **必要條件**
>
> - 你的帳號已啟用快照功能。目前僅限邀請制：[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們以請求存取權限。
> - 一個<.localized_link href="/guides/get-started/generated-xcode-project">已連線至 Tuist</.localized_link>的專案。
> - 需要 iOS 17 或 macOS 14 才能渲染預覽。

[tuist/snapshots](https://github.com/tuist/snapshots) 程式庫會將你應用程式中的每個 SwiftUI 預覽渲染為圖片，因此你無需手動撰寫快照測試。`tuist test` 會在執行後上傳圖片，而 Tuist 會將它們與<.localized_link href="/guides/features/snapshots#how-it-works">基準線</.localized_link>進行比較。

## 設定 {#set-up}

將套件加入 `Tuist/Package.swift`：

```swift
let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/tuist/snapshots", .upToNextMinor(from: "0.1.0")),
    ]
)
```

接著新增一個相依於你的應用程式與 `TuistSnapshotsTesting` 的單元測試目標，以及一個執行該目標的配置方案。該配置方案會命名快照集合：

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // Your app target, named "App".
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-snapshot-tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/AppSnapshotTests/**"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TuistSnapshotsTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppSnapshots",
            buildAction: .buildAction(targets: [.target("App")]),
            testAction: .targets([.testableTarget(target: "AppSnapshotTests")])
        ),
    ]
)
```

在目標中加入測試類別。每個預覽都會成為獨立的測試：

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

執行 `tuist install` 以取得套件。

## 執行 {#run}

使用 `tuist test` 執行配置方案，並務必在同一個模擬器上執行，因為不同裝置會渲染出不同尺寸的圖片：

```bash
tuist test AppSnapshots --device "iPhone 17"
```

在 CI 中，測試所渲染的圖片會在執行後上傳；若圖片發生變更且無人核准，指令將會失敗。本機執行不會上傳任何內容，因為這會上傳未提交的變更。

> [!TIP]
> 透過<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>，快照測試目標僅在其圖片通過或已獲核准時才會被略過，因此重新執行不會略過無人審查變更的目標。當一次執行略過某些目標時，其未渲染的圖片會被計為略過，而非移除。

<!-- @snippet: ./_previews-library -->
