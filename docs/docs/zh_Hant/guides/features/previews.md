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

在建立應用程式時，您可能想要與他人分享以獲得回饋。傳統上，團隊會透過建立、簽署並將應用程式推送至 Apple 的
[TestFlight](https://developer.apple.com/testflight/)
等平台來達成這個目的。然而，這個過程可能既麻煩又緩慢，尤其是當您只想從同事或朋友那裡快速獲得回饋時。

為了讓這個過程更為精簡，Tuist 提供了一種方法來產生您的應用程式並與任何人分享預覽。

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
為裝置建置時，目前由您負責確保應用程式已正確簽署。我們計劃在未來簡化這項工作。
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

此指令會產生一個連結，您可以分享給任何人，讓他們在模擬器或實際裝置上執行應用程式。他們只需執行以下指令即可：

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

分享`.ipa` 檔案時，您可以使用預覽連結直接從行動裝置下載應用程式。`.ipa` 預覽的連結預設為_公開_
。將來，您將可選擇將其設定為隱私，因此連結的接收者需要使用其 Tuist 帳戶進行驗證才能下載應用程式。

`tuist run` 也可讓您根據指定符號執行最新預覽，例如`latest` 、分支名稱或特定的提交雜湊：

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
確保`CFBundleVersion` (建置版本) 是唯一的，方法是利用大多數 CI 供應商揭露的 CI run 編號。例如，在 GitHub Actions
中，您可以將`CFBundleVersion` 設定為 <code v-pre>${{ github.run_number }}</code> 變數。

上傳具有相同二進位 (build) 和相同`CFBundleVersion` 的預覽將會失敗。
<!-- -->
:::

## 曲目{#tracks}

軌道可讓您將預覽組織為已命名的群組。例如，您可以為內部測試人員設定`beta` 軌道，為自動化建置設定`nightly` 軌道。軌道可輕鬆建立 -
只需在分享時指定軌道名稱，如果不存在，就會自動建立。

若要在特定音軌上分享預覽，請使用`--track` 選項：

```bash
tuist share App --track beta
tuist share App --track nightly
```

這對以下方面很有用
- **組織預覽** ：依目的將預覽分組 (例如`beta`,`nightly`,`internal`)
- **應用程式內更新** ：Tuist SDK 使用軌跡來決定通知使用者哪些更新
- **篩選** ：在 Tuist 面板中輕鬆地按音軌尋找和管理預覽

::: warning PREVIEWS' VISIBILITY
<!-- -->
只有擁有專案所屬組織存取權限的人才能存取預覽。我們計劃新增對過期連結的支援。
<!-- -->
:::

## Tuist macOS 應用程式{#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

為了讓執行 Tuist 預覽更加容易，我們開發了一個 Tuist macOS 功能表應用程式。與其透過 Tuist CLI 執行預覽，您可以[下載](https://tuist.dev/download) macOS 應用程式。您也可以執行 `brew install --cask tuist/tuist/tuist` 來安裝應用程式。

當您現在點選預覽頁面中的「執行」時，macOS 應用程式會自動在您目前選取的裝置上啟動。

::: warning REQUIREMENTS
<!-- -->
您需要在本機安裝 Xcode，並使用 macOS 14 或更新版本。
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

與 macOS 應用程式類似，Tuist iOS 應用程式可簡化存取和執行預覽的程序。

## 拉取/合併請求註解{#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
若要取得自動的 pull/merge 請求註解，請將您的 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 專案</LocalizedLink>與 <LocalizedLink href="/guides/server/authentication">Git 平台</LocalizedLink>整合。
<!-- -->
:::

測試新功能應該是任何程式碼檢閱的一部分。但必須在本機建立應用程式會增加不必要的摩擦，通常會導致開發人員完全跳過在裝置上測試功能。但是*如果每個拉取請求都包含一個連結，可以讓您在 Tuist macOS 應用程式中選擇的裝置上自動執行應用程式的建立呢？*

一旦您的 Tuist 專案與 [GitHub](https://github.com) 等 Git 平台連線，請在 CI 工作流程中加入 <LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink>。之後，Tuist 會直接在您的拉取請求中發佈預覽連結：

![帶有 Tuist 預覽連結的 GitHub 應用程式註解](/images/guides/features/github-app-with-preview.png)


## 應用程式內更新通知{#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) 可讓您的應用程式偵測更新的預覽版本，並通知使用者。這對於讓測試人員使用最新版本非常有用。

SDK 會檢查同一**預覽軌** 內的更新。當您使用`--track` 與明確的軌道分享預覽時，SDK 會在該軌道上尋找更新。如果沒有指定軌道，則會使用 git
分支作為軌道 - 因此從`main` 分支建立的預覽，只會通知同樣從`main` 建立的更新預覽。

### 安裝{#sdk-installation}

新增 Tuist SDK 為 Swift 套件相依性：

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### 監控更新{#sdk-monitor-updates}

使用`monitorPreviewUpdates` 來定期檢查新的預覽版本：

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

### 停止更新監控{#sdk-stop-monitoring}

`monitorPreviewUpdates` 會傳回`任務` ，該任務可以取消：

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
在模擬器和 App Store 版本上，更新檢查會自動停用。
<!-- -->
:::

## README 徽章{#readme-badge}

為了讓 Tuist 預覽在您的儲存庫中更顯眼，您可以在`README` 檔案中加入徽章，指向最新的 Tuist 預覽：

[![Tuist 預覽](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

若要在`README` 中加入徽章，請使用下列 markdown，並將帳號和專案句柄換成您自己的：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

如果您的專案包含多個具有不同 bundle 識別碼的應用程式，您可以透過新增`bundle-id` 查詢參數，指定要連結到哪個應用程式的預覽：
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## 自動化{#automations}

您可以使用`--json` 標記，從`tuist share` 指令取得 JSON 輸出：
```
tuist share --json
```

JSON 輸出對於建立自訂自動化非常有用，例如使用您的 CI 提供者張貼 Slack 訊息。JSON 包含一個`url`
key，內含完整的預覽連結，以及`qrCodeURL` key，內含 QR 碼影像的 URL，以便更輕鬆地從實體裝置下載預覽。以下是 JSON 輸出的範例：
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
