---
{
  "title": "使用 iPhone App 執行預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "透過 Tuist iOS App 尋找、篩選並存取 Apple 預覽。"
}
---
# 使用 iPhone App 執行預覽

從 App Store 安裝 [Tuist iOS App](https://apps.apple.com/us/app/tuist/id6748460335)，即可尋找並存取你的 Apple 預覽。發布流程的簽署與裝置資格要求仍然適用。

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="在 App Store 下載" style="height: 40px;">
    </a>
</div>

依 App 名稱或版本說明搜尋，然後選擇軌道以篩選預覽。選擇 **全部** 可瀏覽所有軌道，包括未指派軌道的預覽。開啟預覽以閱讀完整的版本說明。

## 用戶端與伺服器相容性 {#client-and-server-compatibility}

保持 Tuist App 為最新版本。若你自行託管 Tuist，請更新伺服器以使用軌道篩選與版本說明功能。在較舊的伺服器上，你仍可瀏覽未經篩選的預覽。

## App 內更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) 讓你的 Apple App 能夠偵測較新的預覽並通知測試人員。它會在相同的 **預覽軌道** 內檢查更新。對於使用 `tuist share --track` 發布的預覽，系統會使用該明確指定的軌道。若未指定軌道，則使用 Git 分支；因此，從 `main` 建置的預覽只會通知來自 `main` 的較新預覽。

### 安裝 {#sdk-installation}

將 Tuist SDK 新增為 Swift Package 相依性：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 監控更新 {#sdk-monitor-updates}

使用 `monitorPreviewUpdates` 定期檢查新的預覽版本：

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

用於手動檢查更新：

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
> 在模擬器與 App Store 建置中，更新檢查會自動停用。
