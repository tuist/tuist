---
{
  "title": "生成的 Xcode 項目",
  "titleTemplate": ":title · 快照 · 功能 · 指南 · Tuist",
  "description": "為 Tuist 生成項目的每個 SwiftUI 預覽建立快照，並在 Tuist 中檢視變更。"
}
---
# 生成嘅 Xcode 專案快照 {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **要求**
>
> - 你嘅帳戶已啟用快照功能。目前只限邀請使用：[聯絡我哋](mailto:contact@tuist.dev)或喺[社區 Slack](https://slack.tuist.dev)留言申請存取權限。
> - 一個<.localized_link href="/guides/get-started/generated-xcode-project">已連接至 Tuist</.localized_link>嘅專案。
> - 需要 iOS 17 或 macOS 14 先至可以渲染預覽。

[tuist/snapshots](https://github.com/tuist/snapshots) 程式庫會將你應用程式入面每個 SwiftUI 預覽渲染成圖片，所以你唔使手動編寫快照測試。`tuist test` 會喺運行結束後上載圖片，而 Tuist 會將佢哋同<.localized_link href="/guides/features/snapshots#how-it-works">基準</.localized_link>進行比較。

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

然後加入一個單元測試目標，佢依賴你嘅應用程式同 `TuistSnapshotsTesting`，並建立一個執行佢嘅 scheme。該 scheme 會命名快照集合：

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

向目標加入測試類別。每個預覽都會成為獨立嘅測試：

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

執行 `tuist install` 以獲取套件。

## 執行 {#run}

使用 `tuist test` 執行 scheme，並且務必使用同一個模擬器，因為唔同裝置渲染出嚟嘅圖片尺寸會唔同：

```bash
tuist test AppSnapshots --device "iPhone 17"
```

喺 CI 環境中，測試渲染嘅圖片會喺運行結束後上載；如果圖片有變更而無人核准，指令就會失敗。本地運行不會上載任何內容，因為咁樣會上載未提交嘅變更。

> [!TIP]
> 透過<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>，只有當快照測試目標嘅圖片通過或已獲核准時，先會跳過該目標，所以重新運行唔會跳過無人審查變更嘅目標。當一次運行跳過若干目標時，佢無渲染嘅圖片會計為「已跳過」，而唔係「已移除」。

<!-- @snippet: ./_previews-library -->
