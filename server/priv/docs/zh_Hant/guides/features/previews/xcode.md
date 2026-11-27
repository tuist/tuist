---
{
  "title": "Xcode 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "分享來自現有 Xcode 專案和 Tuist 產生專案的應用程式預覽。"
}
---
# Xcode 預覽

建置你的應用程式，然後使用 `tuist share` 將其發布到你的 Tuist 專案。請先參照 <.localized_link href="/guides/get-started/existing-xcode-project">現有 Xcode 專案</.localized_link> 或 <.localized_link href="/guides/get-started/generated-xcode-project">已產生專案</.localized_link> 指南來連接你的專案。

## 建置與分享

針對由 Tuist 產生的專案：

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

針對現有的 Xcode 專案：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

將 scheme、專案和 workspace 名稱替換為你自己的名稱。若要分享 Release 建置，在建置時使用 `-configuration Release`，並在分享時使用 `--configuration Release`。

## 實體裝置

你必須負責使用允許在接收者裝置上安裝的佈建設定檔（provisioning profile）來簽署裝置建置。請使用裝置目的地而非模擬器 SDK 進行建置：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

你也可以分享已匯出的 IPA：

```bash
tuist share App.ipa
```

接收者可以在其行動裝置上開啟 IPA 預覽連結以安裝應用程式。驗證機制與專案的預覽可見性設定仍然適用。

## CI 與建置編號

使用你現有的 <.localized_link href="/guides/integrations/continuous-integration">CI 驗證</.localized_link>，並讓每個新建置的 `CFBundleVersion` 保持唯一。例如，使用 GitHub Actions 的 <code v-pre>${{ github.run_number }}</code>。若透過 `tuist share` 再次上傳相同的二進位檔與建置編號，將會失敗而不會建立重複項目。

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

請參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link> 以了解如何執行已發布的建置、存取權限、追蹤軌道以及 README 徽章。

<!-- @snippet: ./_tuist-share -->

接收者可以獨立於建置系統整合之外，使用 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 應用程式</.localized_link> 或 <.localized_link href="/guides/features/previews/run/ios">iPhone 應用程式</.localized_link>。iPhone 指南也涵蓋了搭配 Tuist SDK 的 <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">應用程式內更新通知</.localized_link>。
