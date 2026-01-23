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

開發應用程式時，您可能需要與他人分享以獲取反饋。傳統做法是團隊透過建置、簽署應用程式，並將其推送至如 Apple 的
[TestFlight](https://developer.apple.com/testflight/)
等平台。然而此流程可能繁瑣且耗時，尤其當您僅需從同事或朋友處快速獲取意見時。

為使流程更流暢，Tuist 提供生成應用程式預覽並與任何人共享的功能。

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
當為裝置進行建置時，目前需由您自行確保應用程式簽署正確。我們計劃在未來簡化此流程。
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

此指令將產生可供任何人分享的應用程式執行連結——無論在模擬器或實體裝置上皆可運行。使用者僅需執行以下指令：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`` 分享`.ipa` 檔案時，可透過預覽連結直接從行動裝置下載應用程式。預覽連結預設為_private_ ，意即接收者需使用 Tuist
帳戶驗證方能下載。若需公開分享，可於專案設定中將權限改為公開。

`執行 tuist run` 亦可根據指定參數運行最新預覽，例如：`latest` 、分支名稱或特定提交雜湊值：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
請透過運用多數 CI 供應商公開的 CI 執行編號，確保 ``` 的 `CFBundleVersion`（` ，即建置版本）具有唯一性。例如在 GitHub
Actions 中，可將 ``` 的 `CFBundleVersion`（` ）設定為 `<code v-pre>${{ github.run_number
}}</code>` 變數。

上傳預覽檔時，若使用相同二進位檔（建置版本）且`的CFBundleVersion為` ，系統將判定為失敗。
<!-- -->
:::

## 曲目{#tracks}

軌道功能可讓您將預覽版本組織成命名群組。例如：您可為內部測試人員建立「`beta」` 軌道，並為自動化建置建立「`nightly」`
軌道。軌道採延遲建立機制——分享時僅需指定軌道名稱，若該名稱不存在則會自動建立。

若要分享特定音軌的預覽，請使用 ``--track` ` 選項：

```bash
tuist share App --track beta
tuist share App --track nightly
```

此規則適用於：
- **預覽組織方式**: 依用途分組預覽（例如：`beta`,`nightly`,`internal` ）
- **應用程式內更新**: Tuist SDK 透過追蹤機制決定需通知用戶的更新項目
- **篩選**: 在 Tuist 儀表板中輕鬆按曲目查找與管理預覽

::: warning PREVIEWS' VISIBILITY
<!-- -->
僅限具備專案所屬組織存取權限者可預覽內容。我們計劃新增連結失效功能。
<!-- -->
:::

## Tuist macOS 應用程式{#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

為使執行 Tuist 預覽更為簡便，我們開發了 Tuist macOS 選單列應用程式。您可透過下載 macOS 應用程式取代使用 Tuist CLI
執行預覽功能。亦可執行以下指令安裝應用程式：`brew install --cask tuist/tuist/tuist`

當您在預覽頁面點擊「執行」按鈕時，macOS 應用程式將自動在您當前選定的裝置上啟動該功能。

::: warning REQUIREMENTS
<!-- -->
您需在本地安裝 Xcode 並使用 macOS 14 或更新版本。
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

與 macOS 應用程式類似，Tuist iOS 應用程式能簡化預覽的存取與執行流程。

## 拉取/合併請求註解{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
若要取得自動的 pull/merge 請求註解，請將您的
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist
專案</LocalizedLink>與 <LocalizedLink href="/guides/server/authentication">Git
平台</LocalizedLink>整合。
<!-- -->
:::

測試新功能應是程式碼審查的必備環節。然而，必須在本地端建置應用程式會增加不必要的摩擦，導致開發者往往完全跳過在裝置上測試功能的步驟。但*，如果每個拉取請求都包含一個連結，能自動在您於Tuist
macOS應用程式中選定的裝置上執行應用程式，會如何呢？*

當您的 Tuist 專案與 Git 平台（如 [GitHub](https://github.com)）完成連結後，請在 CI 工作流程中加入
<LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink>。Tuist
將自動在您的拉取請求中嵌入預覽連結：![GitHub app comment with a Tuist Preview
link](/images/guides/features/github-app-with-preview.png)


## 應用程式內更新通知{#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk)
可讓您的應用程式偵測更新的預覽版本是否可用，並通知使用者。此功能有助於讓測試人員保持在最新版本。

SDK會在同一預覽分支內檢查更新：**預覽分支** 當您透過`--track`
明確指定分支分享預覽時，SDK將僅檢查該分支的更新。若未指定分支，則以git分支作為預覽分支——因此從`主分支` 建立的預覽，僅會通知來自`主分支`
的更新預覽。

### 安裝{#sdk-installation}

將 Tuist SDK 添加為 Swift Package 依賴項：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 監控更新{#sdk-monitor-updates}

使用 ``` 並啟用 `monitorPreviewUpdates` (` ) 設定，即可定期檢查新預覽版本：

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

手動檢查更新時：

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

`monitorPreviewUpdates` 會回傳一個可取消的`任務` ：

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
更新檢查功能在模擬器及 App Store 版本中會自動停用。
<!-- -->
:::

## README 徽章{#readme-badge}

為使 Tuist Previews 在您的儲存庫中更顯眼，您可在`README 文件中添加徽章，該徽章將指向最新的 Tuist Preview：`

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

若要在您的`README` 中添加徽章，請使用以下 Markdown 並將帳戶與專案名稱替換為您的實際資訊：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

若您的專案包含多個具有不同套件識別碼的應用程式，可透過添加`bundle-id` 查詢參數來指定連結至哪個應用程式的預覽：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化{#automations}

` 您可使用 ``--json` 旗標，透過 `` ` 指令從 ``` 取得 JSON 輸出：
```
tuist share --json
```

JSON輸出格式可協助建立自訂自動化流程，例如透過持續整合服務商發佈Slack訊息。此JSON包含：- 完整預覽連結的`url` 鍵值-
含QR碼圖片網址的`qrCodeURL` 鍵值便於從實體裝置下載預覽內容。JSON輸出範例如下：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
