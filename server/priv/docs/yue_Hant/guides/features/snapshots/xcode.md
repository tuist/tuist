---
{
  "title": "Xcode",
  "titleTemplate": ":title · 快照 · 功能 · 指南 · Tuist",
  "description": "為 Xcode 專案嘅每個 SwiftUI 預覽建立快照，並喺 Tuist 檢視變更。"
}
---
# Xcode 快照 {#xcode-snapshots}

> [!IMPORTANT]
> **要求**
>
> - 你的帳戶已啟用快照功能。目前僅限邀請：[聯絡我們](mailto:contact@tuist.dev)或在[社區 Slack](https://slack.tuist.dev)上留言以申請存取權限。
> - 一個<.localized_link href="/guides/get-started/existing-xcode-project">已連接到 Tuist</.localized_link>的專案。
> - 需要 iOS 17 或 macOS 14 才能渲染預覽。

[tuist/snapshots](https://github.com/tuist/snapshots) 函式庫會將你應用程式中的每個 SwiftUI 預覽渲染為圖片，因此你無須手動編寫快照測試。`tuist xcodebuild test` 會在執行後上傳圖片，而 Tuist 會將它們與<.localized_link href="/guides/features/snapshots#how-it-works">基準線</.localized_link>進行比較。

## 設定 {#set-up}

1. 在 Xcode 中，加入 `https://github.com/tuist/snapshots` 套件，版本從 `0.1.0` 開始。
2. 建立一個由你的應用程式託管的單元測試目標，例如 `AppSnapshotTests`，並將套件的 `TuistSnapshotsTesting` 產品連結到該目標。
3. 在該目標中加入一個測試類別。每個預覽都會成為其自身的測試：

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

4. 加入一個執行該目標的配置方案，例如 `AppSnapshots`。該配置方案會命名快照集。

## 執行 {#run}

透過 `tuist xcodebuild test` 執行測試，並務必使用同一個模擬器，因為不同裝置渲染出的圖片尺寸會不同：

```bash
tuist xcodebuild test -scheme AppSnapshots -destination 'platform=iOS Simulator,name=iPhone 17'
```

在 CI 中，測試渲染的圖片會在執行後上傳，當圖片發生變更且無人核准時，指令會失敗。本機執行不會上傳任何內容，因為這會上傳未提交的變更。

<!-- @snippet: ./_previews-library -->
