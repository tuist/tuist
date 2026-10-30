---
{
  "title": "Previews",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Previews 即時分享 iOS 和 Android 應用程式構建。只需向隊友和利害關係人提供連結，無需設定 TestFlight 或 Play Console。"
}
---
# Previews {#previews}

Tuist Previews 讓你生成並分享 App 預覽，讓團隊成員無需在本機重新編譯即可測試構建。

在構建 App 時，你可能希望將其分享給他人以獲取反饋。傳統上，團隊會通過構建、簽署並將 App 推送到像 Apple 的 [TestFlight](https://developer.apple.com/testflight/) 等平台來完成這一過程。然而，這個過程可能繁瑣且緩慢，特別是當你只是想從同事或朋友那裡獲得快速反饋時。

為了簡化這一過程，Tuist 提供了一種方法，讓你能够生成並與任何人分享你的 App 預覽。

> [!WARNING]
> **裝置構建需要簽署**
>
> 在為裝置構建時，目前由你負責確保 App 正確簽署。我們計劃在未來簡化這一流程。

::: code-group
```bash [Tuist Project (Debug)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Tuist Project (Release)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release
```
```bash [Xcode Project (Debug)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
```bash [Xcode Project (Release)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

該命令將生成一個連結，你可以與任何人分享以運行 App——無論是在模擬器還是真實裝置上。他們只需運行以下命令：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

當分享 `.ipa` 檔案時，你可以使用預覽連結直接從移動裝置下載 App。`.ipa` 預覽的連結默認為 _私有_，這意味著接收者需要使用其 Tuist 帳戶進行身份驗證才能下載 App。如果你希望與任何人分享 App，可以在項目設置中將其更改為公開。

`tuist run` 還允許你基於指定符（如 `latest`、分支名稱或特定的提交哈希）運行最新的預覽：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **CI 中的唯一構建版本號**
>
> 通過利用大多數 CI 提供商提供的 CI 運行編號，確保 `CFBundleVersion`（構建版本）是唯一的。例如，在 GitHub Actions 中，你可以將 `CFBundleVersion` 設置為 <code v-pre>${{ github.run_number }}</code> 變量。 
>
> 上傳具有相同二進制文件（構建）和相同 `CFBundleVersion` 的預覽將會失敗。

## Tracks {#tracks}

Tracks 允許你將預覽組織成命名的組。例如，你可能有一個用於內部測試人員的 `beta` track，以及一個用於自動化構建的 `nightly` track。Tracks 是懶加載創建的——只需在分享時指定 track 名稱，如果它不存在，系統將自動創建。

要在特定 track 上分享預覽，請使用 `--track` 選項：

```bash
tuist share App --track beta
tuist share App --track nightly
```

這對於以下情況很有用：
- **組織預覽**：按用途對預覽進行分組（例如，`beta`、`nightly`、`internal`）
- **App 內更新**：Tuist SDK 使用 tracks 來確定要通知用戶哪些更新
- **過濾**：在 Tuist 儀表板中輕鬆按 track 查找和管理預覽

> [!WARNING]
> **預覽的可見性**
>
> 只有能夠訪問項目所屬組織的人才能訪問預覽。我們計劃添加對過期連結的支持。

## Release notes {#release-notes}

使用 tracks 進行環境分組，並使用 release notes 說明單次構建的目的：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Release notes 是可選的純文本，最多 10,000 個字符。第一行非空行將作為單行片段顯示在 Web 和 iOS 預覽列表中，因此構建版本號和其他識別信息一目了然。長行會被截斷；完整筆記顯示在詳情頁面上。兩個列表中的搜索都會匹配顯示名稱和完整的 release notes，包括未在片段中顯示的行。支持多行筆記，例如 `--release-notes "$(< release-notes.txt)"`。它們不會改變 App 的顯示名稱或其 track。

### Compatibility {#preview-metadata-compatibility}

Release notes 是附加元數據，不是預覽身份的一部分。來自舊客戶端和新客戶端的上傳仍然在各個平台中歸組到同一個預覽。保留第一行非空筆記：後續上傳可以填充之前缺失的筆記，但不能覆蓋現有筆記。省略 `release_notes`、發送 `null` 或發送空字符串或僅包含空格的字符串永遠不會清除筆記。現有預覽不會回填，且在沒有筆記的情況下仍然有效。

列表 API 的可選 `track` 查詢參數會匹配整個 track 名稱，不區分大小寫，與現有的 track 存儲一致。省略它或發送空值（`?track=`）以列出所有 tracks。Track 名稱仍然是開放字符串，而不是固定的值列表。iOS App 的 **All Tracks** 選擇會省略過濾器。iOS App 的 track 標籤會從 `GET /api/projects/:account_handle/:project_handle/previews/tracks` 加載完整的項目摘要，其權限與列出構建時的預覽讀取權限相同。該端點返回 `{total_count, tracks: [{name, count}]}`，其中包含排序後且不區分大小寫分組的命名 tracks。計數涵蓋整個項目，獨立於分頁、搜索和所選 track；總數包括未追蹤的預覽。僅計算具有 bundle identifier 的可列出的預覽。列表 API 還接受可選的 `search`，用於匹配顯示名稱或完整 release notes 的文字子字符串（不區分大小寫），並在分頁前與 track 組合。現有的 `display_name` 過濾保持精確匹配。

舊客戶端可以繼續上傳和列出預覽，而無需發送任一字段。新客戶端接受省略 track 或筆記的舊響應，並忽略未來服務器添加的未知響應屬性。API 集成也應忽略未知響應屬性，以便附加元數據保持兼容。

自託管部署需要支持 release notes 和 track 過濾的服務器版本，以及更新的 CLI 和 App，才能使用這些功能。較舊的服務器可能會忽略筆記或未知的查詢參數。如果無法發現 track，iOS App 將保持未過濾瀏覽可用，並解釋選擇 track 需要更新服務器。如果服務器在激活過濾器的情況下仍返回其他 track 的預覽，iOS App 將報告不支持過濾，而不是呈現误导性結果。macOS App 首先請求每個 App 的最新兼容預覽；在應用平台過濾器之前選擇不同 App 的較舊服務器上，它會回退到分頁歷史記錄，而不施加可能隱藏可用構建的截止條件。

## Tuist macOS app {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

為了讓運行 Tuist Previews 更加容易，我們開發了 Tuist macOS 菜單欄 App。你可以[下載](https://tuist.dev/download) macOS App，而不是通過 Tuist CLI 運行 Previews。你也可以通過運行 `brew install --cask tuist/tuist/tuist` 來安裝該 App。

當你在預覽頁面點擊「Run」時，macOS App 會自動在你目前選擇的裝置上啟動它。

## Tuist iOS app {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="在 App Store 下載" style="height: 40px;">
    </a>
</div>

與 macOS App 類似，Tuist iOS App 簡化了存取和運行預覽的流程。每個預覽都會顯示其 track。使用原生搜尋欄位按 App 名稱尋找預覽，然後在 **Tracks** 下選擇一個標籤以按環境篩選。選中的標籤會顯示為紫色；選擇 **All** 可移除 track 篩選器。每個標籤都會顯示整個專案的預覽數量，而 All 包含沒有 track 的構建。搜尋和 track 篩選適用於所有頁面，不僅限於已載入的預覽。每個構建的 track 標籤位於其 commit hash 旁邊。

## Pull/merge request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要與 Git 平台整合**
>
> 要獲得自動的 pull/merge request 評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">remote project</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git platform</.localized_link> 整合。

測試新功能應該是任何代碼審查的一部分。但必須在本地構建 App 會增加不必要的摩擦，往往導致開發者完全跳過在裝置上測試功能。但如果*每個 pull request 都包含一個指向構建的連結，該連結會自動在你於 Tuist macOS App 中選擇的裝置上運行 App，那會怎樣？*

一旦你的 Tuist 專案與你的 Git 平台（例如 [GitHub](https://github.com)）連接，請在你的 CI 工作流程中加入 <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link>。Tuist 隨後會直接在你的 pull requests 中發布預覽連結：![帶有 Tuist 預覽連結的 GitHub app 評論](/images/guides/features/github-app-with-preview.png)

## App 內更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) 讓你的 App 能夠偵測何時有新的預覽版本可用並通知用戶。這有助於讓測試人員保持在最新構建上。

SDK 會在同一個 **preview track** 內檢查更新。當你使用 `--track` 並指定 explicit track 來分享預覽時，SDK 會查找該 track 上的更新。如果未指定 track，則使用 git branch 作為 track — 因此，從 `main` branch 構建的預覽只會通知同樣從 `main` 構建的較新預覽。

### 安裝 {#sdk-installation}

將 Tuist SDK 添加為 Swift Package 依賴項：

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

`monitorPreviewUpdates` 返回一個可取消的 `Task`：

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> 在模擬器和 App Store 構建中，更新檢查會自動禁用。

## README badge {#readme-badge}

為了讓 Tuist Previews 在你的儲存庫中更顯眼，你可以在 `README` 文件中添加一個指向最新 Tuist Preview 的 badge：

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

要將 badge 添加到你的 `README`，請使用以下 markdown 並將 account 和 project handle 替換為你自己的：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

如果你的專案包含多個具有不同 bundle identifier 的 App，你可以通過添加 `bundle-id` 查詢參數來指定要連結到哪個 App 的預覽：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化 {#automations}

你可以使用 `--json` 標誌從 `tuist share` 命令獲取 JSON 輸出：
```
tuist share --json
```

JSON 輸出對於創建自定義自動化非常有用，例如使用你的 CI 提供者發布 Slack 消息。JSON 包含一個帶有完整預覽連結的 `url` 鍵和一個帶有 QR code 圖片 URL 的 `qrCodeURL` 鍵，以便更容易從真實裝置下載預覽。以下是 JSON 輸出的示例：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
