---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# 預覽{#previews}

::: warning REQUIREMENTS
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
<!-- -->
:::

在開發應用程式時，您可能希望與他人分享以獲取回饋。傳統上，團隊會透過建置、簽署並將應用程式推送至 Apple 的
[TestFlight](https://developer.apple.com/testflight/)
等平台來達成此目的。然而，這個過程可能既繁瑣又耗時，尤其是當您只是想從同事或朋友那裡獲得快速回饋時。

為了讓這個流程更順暢，Tuist 提供了一種方法，讓您能生成並與任何人分享應用程式的預覽。

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
在針對裝置進行建置時，目前需由您負責確保應用程式已正確簽署。我們計劃在未來簡化此流程。
<!-- -->
:::

::: code-group
```bash [Tuist Project]
tuist generate App
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

此指令將產生一個連結，您可以與任何人分享該連結以執行應用程式——無論是在模擬器上或實際裝置上。對方只需執行以下指令即可：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

分享`.ipa` 檔案時，使用者可透過「預覽」連結直接從行動裝置下載應用程式。預覽連結`.ipa` 預設為_私有_ 狀態，這表示收件者需使用其 Tuist
帳戶進行驗證才能下載應用程式。若您希望與任何人分享此應用程式，可在專案設定中將其設為公開。

`執行 `tuist run` ` 亦可讓您根據指定條件（例如 ``latest`、```、分支名稱或特定提交哈希值）來執行最新預覽版本：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
請利用大多數 CI 服務商所提供的 CI 執行編號，確保 ``` 的 `CFBundleVersion`（` ，即建置版本）具有唯一性。例如，在 GitHub
Actions 中，您可以將 ``` 的 `CFBundleVersion`（` ）設定為 `<code v-pre>${{ github.run_number
}}</code>` 變數。

若上傳的預覽檔與原始二進位檔（建置）及 CFBundleVersion 版本（`）` 相同，上傳將失敗。
<!-- -->
:::

## 曲目{#tracks}

「追蹤」功能可讓您將預覽內容整理成命名群組。例如，您可以為內部測試人員建立一個「`beta` 」追蹤，並為自動化建置建立一個「`nightly`
」追蹤。追蹤會延遲建立——您只需在分享時指定追蹤名稱，若該名稱尚未存在，系統便會自動建立。

若要分享特定音軌的預覽，請使用`--track` 選項：

```bash
tuist share App --track beta
tuist share App --track nightly
```

這對以下情況很有幫助：
- **預覽組織方式**: 依用途分組預覽 (例如：`beta`,`nightly`,`internal`)
- **應用程式內更新**: Tuist SDK 會利用追蹤項目來決定應向使用者通知哪些更新
- **篩選「** 」：在 Tuist 儀表板中輕鬆按曲目查找與管理預覽

::: warning PREVIEWS' VISIBILITY
<!-- -->
僅限該專案所屬組織的成員才能存取預覽內容。我們計劃新增連結過期功能。
<!-- -->
:::

## Tuist macOS 應用程式{#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

為了讓執行 Tuist Previews 更加輕鬆，我們開發了一款 Tuist macOS 選單列應用程式。您無需透過 Tuist CLI 執行
Previews，而是可以 [下載](https://tuist.dev/download) 這款 macOS 應用程式。您也可以透過執行`brew
install --cask tuist/tuist/tuist` 來安裝此應用程式。

現在，當您在「預覽」頁面點擊「執行」時，macOS 應用程式會自動在您目前選定的裝置上啟動該應用程式。

::: warning REQUIREMENTS
<!-- -->
您必須在本地安裝 Xcode，並使用 macOS 14 或更新版本。
<!-- -->
:::

## Tuist iOS 應用程式{#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

與 macOS 應用程式類似，Tuist iOS 應用程式能簡化預覽檔案的存取與執行流程。

## 拉取/合併請求註解{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
若要取得自動的 pull/merge 請求註解，請將您的
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist
專案</LocalizedLink>與 <LocalizedLink href="/guides/server/authentication">Git
平台</LocalizedLink>整合。
<!-- -->
:::

測試新功能應是任何程式碼審查的環節。但必須在本地端建置應用程式會增加不必要的麻煩，往往導致開發者乾脆跳過在裝置上測試功能。但*試想，如果每個拉取請求都包含一個建置連結，能自動在您於
Tuist macOS 應用程式中選定的裝置上執行該應用程式，會如何呢？*

當您的 Tuist 專案與 [GitHub](https://github.com) 等 Git 平台連線後，請在您的 CI 工作流程中加入
<LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink>。Tuist
隨後會直接在您的拉取請求中發布預覽連結：![附有 Tuist 預覽連結的 GitHub
應用程式留言](/images/guides/features/github-app-with-preview.png)


## 應用程式內更新通知{#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk)
可讓您的應用程式偵測是否有較新的預覽版本可用，並通知使用者。這對於讓測試人員保持在最新建置版本上非常有用。

SDK 會檢查同一預覽軌道（**）內的更新** 。當您使用`--track` 分享包含明確軌道的預覽時，SDK 會檢查該軌道的更新。若未指定軌道，則使用 Git
分支作為軌道 —— 因此，從`main` 分支建置的預覽，僅會通知同樣從`main` 分支建置的較新預覽。

### 安裝{#sdk-installation}

將 Tuist SDK 新增為 Swift Package 依賴項：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 請留意更新{#sdk-monitor-updates}

請使用`monitorPreviewUpdates` 定期檢查是否有新的預覽版本：

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

### 單次更新檢查{#sdk-single-check}

關於手動檢查更新：

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### 停止更新監控{#sdk-stop-monitoring}

`monitorPreviewUpdates` 會傳回一個可取消的`任務` ：

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
在模擬器和 App Store 版本中，更新檢查功能會自動停用。
<!-- -->
:::

## README 標章{#readme-badge}

若要讓 Tuist Previews 在您的儲存庫中更顯眼，您可以在`README` 檔案中加入一個標籤，指向最新的 Tuist Preview：

[![Tuist
預覽](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

若要在您的`README` 中加入徽章，請使用以下 Markdown 格式，並將帳戶和專案名稱替換為您自己的：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

若您的專案包含多個具有不同套件識別碼的應用程式，您可以透過新增`bundle-id` 查詢參數，指定要連結至哪個應用程式的預覽：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化{#automations}

您可以使用`--json` 參數，從`tuist share` 指令中取得 JSON 輸出：
```
tuist share --json
```

JSON 輸出對於建立自訂自動化流程非常有用，例如透過您的 CI 服務提供商發送 Slack 訊息。該 JSON 包含一個`url`
鍵，其中包含完整的預覽連結；以及一個`qrCodeURL` 鍵，其中包含 QR 碼圖片的網址，以便更輕鬆地從真實裝置下載預覽。以下為 JSON 輸出的範例：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
