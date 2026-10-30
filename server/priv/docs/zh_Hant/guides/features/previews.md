---
{
  "title": "預覽",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "透過 Tuist Previews 立即分享 iOS 與 Android 應用程式建置。只需提供連結給團隊成員與利害關係人，無需設定 TestFlight 或 Play Console。"
}
---
# Previews {#previews}

Tuist Previews 可讓你產生並分享應用程式預覽，讓團隊成員無需在本機重新建置即可測試建置結果。

在建置應用程式時，你可能希望將其分享給他人以取得回饋。傳統上，團隊會透過建置、簽署並將應用程式推送到 Apple 的 [TestFlight](https://developer.apple.com/testflight/) 等平台來達成此目的。然而，這個流程可能繁瑣且緩慢，特別是你只是想要從同事或朋友那裡獲得快速回饋時。

為了讓此流程更順暢，Tuist 提供了一種方法，可讓你產生並與任何人分享應用程式的預覽。

> [!WARNING]
> **裝置建置需要簽署**
>
> 在為裝置建置時，目前由你負責確保應用程式已正確簽署。我們計畫在未來簡化此流程。

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

該指令會產生一個連結，你可以與任何人分享以執行應用程式——無論是在模擬器或實際裝置上。他們只需執行以下指令：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

當分享 `.ipa` 檔案時，你可以使用預覽連結直接從行動裝置下載應用程式。`.ipa` 預覽的連結預設為 _私密_，表示接收者需要使用其 Tuist 帳號進行驗證才能下載應用程式。若你想將應用程式分享給任何人，可以在專案設定中將其改為公開。

`tuist run` 也讓你能够根據指定條件（例如 `latest`、分支名稱或特定的提交雜湊）執行最新的預覽：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **CI 中的唯一建置編號**
>
> 請利用大多數 CI 供應商提供的 CI 執行編號，確保 `CFBundleVersion`（建置版本）是唯一的。例如，在 GitHub Actions 中，你可以將 `CFBundleVersion` 設定為 <code v-pre>${{ github.run_number }}</code> 變數。 
>
> 上傳具有相同二進位檔（建置）和相同 `CFBundleVersion` 的預覽將會失敗。

## Tracks {#tracks}

Tracks 可讓你將預覽組織成具名的群組。例如，你可能會有用於內部測試人員的 `beta` track，以及用於自動建置的 `nightly` track。Tracks 會延遲建立——只需在分享時指定 track 名稱，若不存在則會自動建立。

若要在特定 track 上分享預覽，請使用 `--track` 選項：

```bash
tuist share App --track beta
tuist share App --track nightly
```

這對於以下情況很有用：
- **組織預覽**：依用途將預覽分組（例如 `beta`、`nightly`、`internal`）
- **應用程式內更新**：Tuist SDK 使用 tracks 來決定要通知使用者哪些更新
- **篩選**：在 Tuist 儀表板中輕鬆依 track 尋找和管理預覽

> [!WARNING]
> **預覽的可見性**
>
> 只有能存取專案所屬組織的人員才能存取預覽。我們計畫新增對過期連結的支援。

## Release notes {#release-notes}

使用 tracks 作為環境群組，並使用 release notes 說明個別建置的目的：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Release notes 是可選的純文字，最多 10,000 個字元。第一個非空白行會在網頁和 iOS 預覽清單中以單行摘要顯示，因此建置編號和其他識別資訊一目了然。長行會被截斷；完整筆記會出現在詳細頁面。兩個清單中的搜尋都會比對顯示名稱和完整 release notes，包括未在摘要中顯示的行。支援多行筆記，例如 `--release-notes "$(< release-notes.txt)"`。它們不會改變應用程式的顯示名稱或其 track。

### Compatibility {#preview-metadata-compatibility}

Release notes 是附加的中繼資料，並非預覽身分的一部分。來自新舊用戶端的上傳仍會跨平台歸類到同一個預覽中。第一個非空白筆記會被保留：後續上傳可以填入先前缺少的筆記，但無法覆寫現有的筆記。省略 `release_notes`、傳送 `null`，或傳送空字串或僅含空白的字串，永遠不會清除筆記。現有的預覽不會回溯填充，且在沒有筆記的情況下仍然有效。

清單 API 的可選 `track` 查詢參數會不分大小寫地比對整個 track 名稱，與現有的 track 儲存方式一致。省略它或傳送空值（`?track=`）以列出所有 tracks。Track 名稱保持為開放字串，而非固定的值列表。iOS 應用程式的 **All Tracks** 選項會省略篩選器。iOS 應用程式的 track 按鈕會從 `GET /api/projects/:account_handle/:project_handle/previews/tracks` 載入完整的專案摘要，其權限與列出建置時的預覽讀取授權相同。該端點會傳回 `{total_count, tracks: [{name, count}]}`，其中包含已排序且不分大小寫分組的具名 tracks。計數涵蓋整個專案，獨立於分頁、搜尋和所選 track；總數包含未追蹤的預覽。僅計算具有 bundle identifier 且可列出的預覽。清單 API 也接受可選的 `search`，用於比對顯示名稱或完整 release notes 中不分大小寫的文字子字串，並在分頁前與 track 結合。現有的 `display_name` 篩選保持精確比對。

舊版用戶端可以繼續上傳和列出預覽，而無需傳送任一欄位。新版用戶端接受省略 track 或筆記的舊版回應，並忽略未來伺服器新增的未知回應屬性。API 整合也應忽略未知的回應屬性，以保持附加中繼資料的相容性。

自託管部署需要支援 release notes 和 track 篩選的伺服器版本，以及更新後的 CLI 和應用程式，才能使用這些功能。較舊的伺服器可能會忽略筆記或未知的查詢參數。若無法發現 track，iOS 應用程式會保持未篩選的瀏覽功能可用，並說明選擇 track 需要更新的伺服器。若伺服器在啟用篩選器的情況下仍傳回其他 track 的預覽，iOS 應用程式會報告不支援篩選，而非呈現誤導性的結果。macOS 應用程式會先請求每個應用程式的最新相容預覽；在套用平台篩選器前先選擇不同應用程式的較舊伺服器上，它會退回至分頁歷史記錄，而不施加可能隱藏可用建置的截止點。

## Tuist macOS app {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

為了讓執行 Tuist Previews 更加容易，我們開發了 Tuist macOS 選單列應用程式。與其透過 Tuist CLI 執行 Previews，你可以[下載](https://tuist.dev/download) macOS 應用程式。你也可以透過執行 `brew install --cask tuist/tuist/tuist` 來安裝該應用程式。

當你在預覽頁面點擊「執行」時，macOS 應用程式會自動在你目前選取的裝置上啟動它。

## Tuist iOS app {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="在 App Store 下載" style="height: 40px;">
    </a>
</div>

與 macOS 應用程式類似，Tuist iOS 應用程式簡化了存取和執行預覽的流程。每個預覽都會顯示其 track。使用原生搜尋欄位依應用程式名稱尋找預覽，然後在 **Tracks** 下方選擇藥丸狀標籤以依環境篩選。選取的標籤會呈現紫色；選擇 **All** 即可移除 track 篩選器。每個標籤都會顯示該專案範圍內的預覽數量，而 All 包含沒有 track 的建置。搜尋和 track 篩選會套用於所有頁面，而不僅限於已載入的預覽。每個建置的 track 標籤位於其 commit hash 旁邊。

## Pull/merge request 留言 {#pullmerge-request-comments}

> [!WARNING]
> **需要與 Git 平台整合**
>
> 若要取得自動的 pull/merge request 留言，請將你的 <.localized_link href="/guides/server/accounts-and-projects">遠端專案</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 整合。

測試新功能應成為任何程式碼審查的一部分。但必須在本機建置應用程式會增加不必要的摩擦，常導致開發者完全跳過在裝置上測試功能。但如果*每個 pull request 都包含一個建置連結，能自動在你於 Tuist macOS 應用程式中選取的裝置上執行該應用程式呢？*

一旦你的 Tuist 專案與如 [GitHub](https://github.com) 等 Git 平台連接後，請在你的 CI 工作流程中加入 <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link>。Tuist 隨後會直接在你的 pull requests 中張貼預覽連結：![包含 Tuist 預覽連結的 GitHub 應用程式留言](/images/guides/features/github-app-with-preview.png)

## 應用程式內更新通知 {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) 讓你的應用程式能夠偵測是否有更新的預覽版本並通知使用者。這有助於讓測試人員保持在最新的建置版本上。

SDK 會在相同的 **preview track** 內檢查更新。當你使用 `--track` 並指定明確的 track 來分享預覽時，SDK 將會在該 track 上尋找更新。若未指定 track，則會使用 git branch 作為 track — 因此從 `main` branch 建置的預覽只會通知同樣從 `main` 建置的更新預覽。

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
> 在模擬器和 App Store 建置中，更新檢查會自動停用。

## README 徽章 {#readme-badge}

為了讓 Tuist Previews 在你的儲存庫中更加顯眼，你可以在 `README` 檔案中加入指向最新 Tuist Preview 的徽章：

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

若要將徽章加入你的 `README`，請使用以下 markdown 並將帳號和專案 handle 替換為你自己的：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

如果你的專案包含多個具有不同 bundle identifier 的應用程式，你可以透過新增 `bundle-id` 查詢參數來指定要連結哪個應用程式的預覽：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化 {#automations}

你可以使用 `--json` 旗標從 `tuist share` 命令取得 JSON 輸出：
```
tuist share --json
```

JSON 輸出對於建立自訂自動化很有用，例如使用你的 CI 提供者張貼 Slack 訊息。JSON 包含帶有完整預覽連結的 `url` 金鑰，以及帶有 QR code 圖片 URL 的 `qrCodeURL` 金鑰，以便更輕鬆地從實體裝置下載預覽。以下是 JSON 輸出的範例：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
