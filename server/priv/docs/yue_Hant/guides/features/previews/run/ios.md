---
{
  "title": "用 iPhone App 執行預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "透過 Tuist iOS App 尋找、篩選及存取 Apple 預覽。"
}
---
# 用 iPhone App 執行 Previews

從 [App Store 安裝 Tuist iOS App](https://apps.apple.com/us/app/tuist/id6748460335)，即可尋找並存取你的 Apple Previews。發布流程的簽署與裝置資格要求仍然適用。

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="在 App Store 下載" style="height: 40px;">
    </a>
</div>

按 App 名稱或 Release Notes 搜尋，然後選擇 Track 以篩選 Previews。選擇 **全部** 可瀏覽所有 Track，包括未設定 Track 的 Previews。開啟 Preview 即可查看完整的 Release Notes。

## 用戶端與伺服器相容性 {#client-and-server-compatibility}

保持 Tuist App 為最新版本。如果你自行託管 Tuist，請更新伺服器以支援 Track 篩選與 Release Notes。在較舊的伺服器上，你仍然可以不加篩選地瀏覽 Previews。

## App 內更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) 讓你的 Apple App 能夠偵測較新的 Preview 並通知測試人員。它會在同一個 **Preview Track** 內檢查更新。對於使用 `tuist share --track` 發布的 Previews，系統會使用該明確指定的 Track。如果沒有明確指定 Track，則會使用 Git Branch，因此從 `main` 建構的 Preview 只會通知來自 `main` 的較新 Previews。

### 安裝 {#sdk-installation}

將 Tuist SDK 加入為 Swift Package 依賴項：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 監控更新 {#sdk-monitor-updates}

使用 `monitorPreviewUpdates` 定期檢查新的 Preview 版本：

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### 單次更新檢查 {#sdk-single-check}

如需手動檢查更新：

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### 停止更新監控 {#sdk-stop-monitoring}

`monitorPreviewUpdates` 會回傳一個可取消的 `Task`：

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> 在模擬器與 App Store 建構版本中，更新檢查會自動停用。
