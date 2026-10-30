---
{
  "title": "預覽",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Previews 即時分享 iOS 和 Android 應用程式構建。只需向隊友和利益相關者提供連結，無需設定 TestFlight 或 Play Console。"
}
---
# Previews {#previews}

Tuist Previews 讓你可以生成並分享應用程式預覽，令團隊成員毋須在本機重新編譯即可測試建構。

建構應用程式時，你可能想將它分享給他人以取得回饋。傳統上，團隊會透過建構、簽署並將應用程式推送到 Apple 的 [TestFlight](https://developer.apple.com/testflight/) 等平台來做到這一點。然而，這個過程可能繁瑣且緩慢，尤其是當你只是想從同事或朋友那裡獲得快速回饋時。

為簡化此流程，Tuist 提供了一種方法，讓你生成並與任何人分享應用程式的預覽。

> [!WARNING]
> **裝置建構需要正確簽署**
>
> 當為裝置進行建構時，確保應用程式已正確簽署目前是你的責任。我們計劃在未來簡化此流程。

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

該指令會生成一個連結，你可以將其分享給任何人以執行應用程式——無論是在模擬器還是實際裝置上。他們只需執行以下指令：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

分享 `.ipa` 檔案時，你可以使用預覽連結直接從流動裝置下載應用程式。`.ipa` 預覽的連結預設為 _私密_，即接收者需要使用其 Tuist 帳戶進行驗證才能下載應用程式。如果你想與任何人分享應用程式，可以在專案設定中將其改為公開。

`tuist run` 還允許你根據指定符（例如 `latest`、分支名稱或特定的 commit hash）執行最新的預覽：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **CI 中的唯一建構編號**
>
> 利用大多數 CI 供應商提供的 CI 執行編號，確保 `CFBundleVersion`（建構版本）是唯一的。例如，在 GitHub Actions 中，你可以將 `CFBundleVersion` 設定為 <code v-pre>${{ github.run_number }}</code> 變數。 
>
> 上傳具有相同二進位檔（建構）和相同 `CFBundleVersion` 的預覽將會失敗。

## Tracks {#tracks}

Tracks 讓你可以將預覽組織成命名的群組。例如，你可能有一個用於內部測試人員的 `beta` track，以及一個用於自動化建構的 `nightly` track。Track 會惰性建立——只需在分享時指定 track 名稱，如果它不存在，系統會自動建立。

若要在特定 track 上分享預覽，請使用 `--track` 選項：

```bash
tuist share App --track beta
tuist share App --track nightly
```

這適用於：
- **組織預覽**：按用途分組預覽（例如 `beta`、`nightly`、`internal`）
- **應用程式內更新**：Tuist SDK 使用 tracks 來決定要通知用戶哪些更新
- **篩選**：在 Tuist 儀表板中輕鬆按 track 查找和管理預覽

> [!WARNING]
> **預覽的可見性**
>
> 只有擁有專案所屬組織訪問權限的人才能訪問預覽。我們計劃增加對過期連結的支持。

## Release notes {#release-notes}

使用 tracks 作為環境群組，並使用 release notes 說明單次建構的目的：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Release notes 是可選的純文字，最多 10,000 個字符。第一個非空白行會作為單行摘要出現在網頁和 iOS 預覽列表中，因此建構編號和其他識別資訊一目了然。長行會被截斷；完整筆記會顯示在詳情頁面上。兩個列表中的搜索都會匹配顯示名稱和完整的 release notes，包括未在摘要中顯示的行。支持多行筆記，例如 `--release-notes "$(< release-notes.txt)"`。它們不會改變應用程式的顯示名稱或其 track。

### Compatibility {#preview-metadata-compatibility}

Release notes 是附加的元數據，不是預覽身份的一部分。來自舊版和新版客戶端的上傳仍然會在跨平台時歸入同一個預覽。保留第一個非空白筆記：後續上傳可以填充之前缺少的筆記，但不能覆蓋現有筆記。省略 `release_notes`、發送 `null` 或發送空或僅含空白的字符串永遠不會清除筆記。現有預覽不會回填，且在沒有筆記的情況下仍然有效。

列表 API 的可選 `track` 查詢參數會匹配整個 track 名稱，不區分大小寫，與現有 track 存儲一致。省略它或發送空值（`?track=`）以列出所有 tracks。Track 名稱保持為開放字符串，而不是固定的值列表。iOS 應用程式的 **All Tracks** 選擇會省略篩選器。iOS 應用程式的 track pills 會從 `GET /api/projects/:account_handle/:project_handle/previews/tracks` 加載完整的專案摘要，其權限與列出建構時的預覽讀取授權相同。該端點返回 `{total_count, tracks: [{name, count}]}`，其中包含排序後且不區分大小寫分組的命名 tracks。計數涵蓋整個專案，獨立於分頁、搜索和所選 track；總數包括未追蹤的預覽。僅計算具有 bundle identifier 且可列出的預覽。列表 API 還接受可選的 `search`，用於匹配顯示名稱或完整 release notes 的字面量、不區分大小寫的子字符串，並在分頁前與 track 組合。現有的 `display_name` 篩選保持精確匹配。

舊版客戶端可以繼續上傳和列出預覽，而無需發送任一字段。新版客戶端接受省略 track 或筆記的舊響應，並忽略未來服務器添加的未知響應屬性。API 集成也應忽略未知響應屬性，以便附加元數據保持兼容。

自託管部署需要支持 release notes 和 track 篩選的服務器版本，以及更新後的 CLI 和應用程式，才能使用這些功能。較舊的服務器可能會忽略筆記或未知的查詢參數。如果無法發現 track，iOS 應用程式會保持未篩選的瀏覽可用，並說明選擇 track 需要更新的服務器。如果服務器在活動篩選器生效時仍返回來自其他 track 的預覽，iOS 應用程式會報告不支持篩選，而不是呈現误导性結果。macOS 應用程式首先請求每個應用程式的最新兼容預覽；在應用平台篩選器之前先選擇不同應用程式的較舊服務器上，它會回退到分頁歷史記錄，而不施加可能隱藏可用建構的截止點。

## Tuist macOS app {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

為了讓運行 Tuist Previews 更加容易，我們開發了一款 Tuist macOS 選單列應用程式。與其通過 Tuist CLI 運行 Previews，你可以 [下載](https://tuist.dev/download) macOS 應用程式。你也可以通過運行 `brew install --cask tuist/tuist/tuist` 來安裝該應用程式。

當你在預覽頁面點擊「Run」時，macOS 應用程式會自動在你目前選取的裝置上啟動它。

## Tuist iOS app {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="在 App Store 下載" style="height: 40px;">
    </a>
</div>

與 macOS 應用程式類似，Tuist iOS 應用程式簡化了存取和運行預覽的流程。每個預覽都會顯示其 track。使用原生搜尋欄位按應用程式名稱尋找預覽，然後在 **Tracks** 下方選擇標籤以按環境篩選。選中的標籤為紫色；選擇 **All** 可移除 track 篩選器。每個標籤顯示其專案範圍內的預覽數量，而 All 包含沒有 track 的建構。搜尋和 track 篩選適用於所有頁面，不僅限於已載入的預覽。每個建構的 track 標籤位於其 commit hash 旁邊。

## Pull/merge request comments {#pullmerge-request-comments}

> [!WARNING]
> **需要與 Git 平台集成**
>
> 要獲得自動的 pull/merge request 評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">remote project</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git platform</.localized_link> 集成。

測試新功能應成為任何程式碼審查的一部分。但必須在本地建構應用程式會增加不必要的摩擦，往往導致開發者完全跳過在裝置上測試功能。但是，*如果每個 pull request 都包含一個連結，可以自動在你在 Tuist macOS 應用程式中選取的裝置上運行該應用程式，那會怎樣？*

一旦你的 Tuist 專案與你的 Git 平台（例如 [GitHub](https://github.com)）連接，請在你的 CI 工作流程中添加 <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link>。Tuist 隨後會直接在你的 pull requests 中發布預覽連結：![帶有 Tuist 預覽連結的 GitHub 應用程式評論](/images/guides/features/github-app-with-preview.png)

## 應用程式內更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) 讓你的應用程式能夠檢測何時有新的預覽版本可用並通知用戶。這有助於讓測試人員保持在最新的建構版本上。

SDK 會在相同的 **preview track** 內檢查更新。當你使用 `--track` 共享具有明確 track 的預覽時，SDK 將查找該 track 上的更新。如果未指定 track，則使用 git branch 作為 track — 因此，從 `main` branch 建構的預覽只會通知同樣從 `main` 建構的較新預覽。

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
> 在模擬器和 App Store 建構中，更新檢查會自動禁用。

## README badge {#readme-badge}

為了讓 Tuist Previews 在你的儲存庫中更加可見，你可以在 `README` 文件中添加一個指向最新 Tuist Preview 的 badge：

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

要將 badge 添加到你的 `README`，請使用以下 markdown 並將帳戶和專案 handle 替換為你自己的：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

如果你的專案包含多個具有不同 bundle identifier 的應用程式，你可以通過添加 `bundle-id` 查詢參數來指定要連結到哪個應用程式的預覽：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化 {#automations}

你可以使用 `--json` 標誌從 `tuist share` 命令獲取 JSON 輸出：
```
tuist share --json
```

JSON 輸出對於創建自定義自動化很有用，例如使用你的 CI 提供者發布 Slack 訊息。JSON 包含一個帶有完整預覽連結的 `url` 鍵和一個帶有 QR code 圖片 URL 的 `qrCodeURL` 鍵，以便更輕鬆地從真實裝置下載預覽。以下是 JSON 輸出的示例：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
