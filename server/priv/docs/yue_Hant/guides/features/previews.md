---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Share iOS and Android app builds instantly with Tuist Previews. Give teammates and stakeholders a link, no TestFlight or Play Console setup required."
}
---
# 預覽 {#previews}

Tuist Previews 讓你生成並分享應用程式預覽，讓團隊成員無需在本地重新建構即可測試建構版本。

在建構應用程式時，你可能想與他人分享以獲取回饋。傳統上，團隊會透過建構、簽署並將應用程式推送到如 Apple 的 [TestFlight](https://developer.apple.com/testflight/) 等平台來達成此目的。然而，這個過程可能繁瑣且緩慢，特別是當你只是想從同事或朋友那裡獲得快速回饋時。

為了讓此流程更順暢，Tuist 提供了一種方法，讓你能够生成並與任何人分享你的應用程式預覽。

> [!WARNING]
> **裝置建構需要簽署**
>
> 當為裝置進行建構時，目前由你負責確保應用程式已正確簽署。我們計劃在未來簡化此流程。

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

該指令將生成一個連結，你可以與任何人分享以執行應用程式——無論是在模擬器還是實際裝置上。他們只需執行以下指令：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

當分享 `.ipa` 檔案時，你可以使用預覽連結直接從移動裝置下載應用程式。`.ipa` 預覽的連結預設為 _私密_，這意味著接收者需要使用其 Tuist 帳戶進行驗證才能下載應用程式。如果你想與任何人分享應用程式，可以在專案設定中將其改為公開。

`tuist run` 還允許你根據指定符（例如 `latest`、分支名稱或特定的提交雜湊值）執行最新的預覽：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **Ci 中的唯一建構編號**
>
> 透過利用大多數 CI 提供者提供的 CI 執行編號，確保 `CFBundleVersion`（建構版本）是唯一的。例如，在 GitHub Actions 中，你可以將 `CFBundleVersion` 設定為 <code v-pre>${{ github.run_number }}</code> 變數。 
>
> 上傳具有相同二進位檔（建構）和相同 `CFBundleVersion` 的預覽將會失敗。

## 軌道 {#tracks}

軌道允許你將預覽組織成命名的群組。例如，你可能有一個用於內部測試人員的 `beta` 軌道和一個用於自動建構的 `nightly` 軌道。軌道是懶惰建立的——只需在分享時指定軌道名稱，如果它不存在，它將自動建立。

若要在特定軌道上分享預覽，請使用 `--track` 選項：

```bash
tuist share App --track beta
tuist share App --track nightly
```

這對於以下情況很有用：
- **組織預覽**：按用途將預覽分組（例如 `beta`、`nightly`、`internal`）
- **應用程式內更新**：Tuist SDK 使用軌道來確定要通知用戶哪些更新
- **過濾**：在 Tuist 儀表板中輕鬆按軌道查找和管理預覽

> [!WARNING]
> **預覽的可見性**
>
> 只有擁有專案所屬組織存取權限的人才能存取預覽。我們計劃新增對過期連結的支援。

## 發行說明 {#release-notes}

使用軌道作為環境群組，並使用發行說明作為單個建構的目的：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

發行說明是可選的純文字，最多 10,000 個字元。第一個非空白行會以單行片段的形式出現在網頁和 iOS 預覽列表中，因此建構編號和其他識別資訊一目了然。長行會被截斷；完整說明會出現在詳細頁面上。兩個列表中的搜尋都會比對顯示名稱和完整發行說明，包括未在片段中顯示的行。支援多行說明，例如 `--release-notes "$(< release-notes.txt)"`。它們不會改變應用程式的顯示名稱或其軌道。

### 相容性 {#preview-metadata-compatibility}

發行說明是附加的中繼資料，不是預覽身份的一部分。來自舊版和新版客戶端的上傳仍然在各個平台上歸組到同一個預覽中。保留第一個非空白說明：後續的上傳可以填寫之前缺少的說明，但不能覆蓋現有的說明。省略 `release_notes`、發送 `null` 或發送空或僅包含空白的字串永遠不會清除說明。現有預覽不會回填，並且在沒有說明的情況下仍然有效。

列表 API 的可選 `track` 查詢參數會比對整個軌道名稱，不區分大小寫，與現有的軌道儲存一致。省略它或發送空值（`?track=`）以列出所有軌道。軌道名稱保持為開放字串，而不是固定的值列表。iOS 應用程式的 **所有軌道** 選擇會省略過濾器。iOS 應用程式的軌道標籤會從 `GET /api/projects/:account_handle/:project_handle/previews/tracks` 載入完整的專案摘要，其授權與列出建構時的預覽讀取授權相同。該端點返回 `{total_count, tracks: [{name, count}]}`，其中包含排序後且不區分大小寫分組的命名軌道。計數涵蓋整個專案，獨立於分頁、搜尋和所選軌道；總數包括未追蹤的預覽。只有具有捆綁包識別碼的可列出預覽才會被計數。列表 API 還接受可選的 `search`，用於比對顯示名稱或完整發行說明的文字、不區分大小寫的子字串，並在分頁前與軌道結合。現有的 `display_name` 過濾保持精確。

舊版客戶端可以繼續上傳和列出預覽，而無需發送任一欄位。新版客戶端接受省略軌道或說明的舊版回應，並忽略未來伺服器新增的未知回應屬性。API 整合也應忽略未知的回應屬性，以便附加的中繼資料保持相容。

自託管部署需要支援發行說明和軌道過濾的伺服器版本，以及更新的 CLI 和應用程式，才能使用這些功能。較舊的伺服器可能會忽略說明或未知的查詢參數。如果無法發現軌道，iOS 應用程式會保持未過濾的瀏覽可用，並解釋選擇軌道需要更新的伺服器。如果伺服器在啟用過濾器的情況下仍返回來自其他軌道的預覽，iOS 應用程式會報告不支持過濾，而不是呈現誤導性的結果。macOS 應用程式首先請求每個應用程式的最新相容預覽；在應用平台過濾器之前選擇不同應用程式的較舊伺服器上，它會回退到分頁歷史記錄，而不施加可能隱藏可用建構的截止點。

## Tuist macOS 應用程式 {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

為了讓執行 Tuist Previews 更加容易，我們開發了 Tuist macOS 選單列應用程式。與其透過 Tuist CLI 執行預覽，你可以 [下載](https://tuist.dev/download) macOS 應用程式。你也可以透過執行 `brew install --cask tuist/tuist/tuist` 來安裝該應用程式。

當你在預覽頁面點擊「執行」時，macOS 應用程式會自動在你目前選取的裝置上啟動它。

## Tuist iOS 應用程式 {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="在 App Store 下載" style="height: 40px;">
    </a>
</div>

與 macOS 應用程式類似，Tuist iOS 應用程式簡化了存取和執行預覽的流程。每個預覽都會顯示其軌道。使用原生搜尋欄位按應用程式名稱尋找預覽，然後在 **軌道** 下選擇一個標籤以按環境過濾。選中的標籤為紫色；選擇 **全部** 以移除軌道過濾器。每個標籤顯示其專案範圍內的預覽數量，而「全部」包含沒有軌道的建構。搜尋和軌道過濾適用於所有頁面，而不僅是已載入的預覽。每個建構的軌道標籤位於其提交雜湊旁邊。

## 拉取/合併請求評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要與 Git 平台整合**
>
> 若要取得自動拉取/合併請求評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">遠端專案</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 整合。

測試新功能應成為任何程式碼審查的一部分。但必須在本地建構應用程式會增加不必要的摩擦，往往導致開發者完全跳過在裝置上測試功能。但是，*如果每個拉取請求都包含一個連結到建構的鏈接，該建構會自動在你於 Tuist macOS 應用程式中選取的裝置上執行應用程式，那會怎樣？*

一旦你的 Tuist 專案與你的 Git 平台（例如 [GitHub](https://github.com)）連接，請在你的 CI 工作流程中加入 <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link>。Tuist 隨後會直接在您的拉取請求中發布預覽連結：![帶有 Tuist 預覽連結的 GitHub 應用程式評論](/images/guides/features/github-app-with-preview.png)

## 應用程式內更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) 讓你的應用程式能夠偵測何時有新的預覽版本可用並通知使用者。這對於讓測試人員保持在最新建構上很有用。

SDK 會在相同的 **預覽軌道** 內檢查更新。當你使用 `--track` 共用具有明確軌道的預覽時，SDK 會在該軌道上尋找更新。如果未指定軌道，則使用 git 分支作為軌道——因此從 `main` 分支建構的預覽只會通知也從 `main` 建構的較新預覽。

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

用於手動更新檢查：

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
> 更新檢查在模擬器和 App Store 建構中會自動停用。

## README 徽章 {#readme-badge}

為了讓 Tuist Previews 在你的儲存庫中更加可見，你可以在 `README` 檔案中添加一個指向最新 Tuist Preview 的徽章：

[![Tuist 預覽](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

若要將徽章添加到你的 `README`，請使用以下 markdown 並將帳戶和專案句柄替換為你自己的：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

如果你的專案包含多個具有不同 bundle identifier 的應用程式，你可以透過添加 `bundle-id` 查詢參數來指定要連結到哪個應用程式的預覽：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化 {#automations}

你可以使用 `--json` 標誌從 `tuist share` 命令取得 JSON 輸出：
```
tuist share --json
```

JSON 輸出對於建立自訂自動化很有用，例如使用你的 CI 提供者發布 Slack 訊息。JSON 包含一個帶有完整預覽連結的 `url` 金鑰，以及一個帶有 QR code 圖片 URL 的 `qrCodeURL` 金鑰，以便更輕鬆地從真實裝置下載預覽。以下是 JSON 輸出的範例：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
