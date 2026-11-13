---
{
  "title": "Xcode 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "從現有的 Xcode 專案和 Tuist 產生的專案中分享應用程式預覽。"
}
---
# Xcode 預覽

建置你的應用程式，然後使用 `tuist share` 將其發布到你的 Tuist 專案。請先參閱 <.localized_link href="/guides/get-started/existing-xcode-project">現有 Xcode 專案</.localized_link> 或 <.localized_link href="/guides/get-started/generated-xcode-project">已生成專案</.localized_link> 指南來連接你的專案。

## 建置與分享

適用於由 Tuist 生成的專案：

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

適用於現有的 Xcode 專案：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

將 scheme、專案和 workspace 名稱替換為你自己的。若要分享 Release 建置版本，在建置時使用 `-configuration Release`，在分享時使用 `--configuration Release`。

## 實體裝置

你必須負責使用允許在接收者裝置上安裝的描述檔來簽署裝置建置版本。請針對裝置目的地進行建置，而非使用模擬器 SDK：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

你也可以分享已匯出的 IPA：

```bash
tuist share App.ipa
```

接收者可以在其行動裝置上開啟 IPA 預覽連結以安裝應用程式。身分驗證與專案的預覽可見性設定仍然適用。

## CI 與建置編號

使用你現有的 <.localized_link href="/guides/integrations/continuous-integration">CI 驗證</.localized_link>，並讓每個新建置版本的 `CFBundleVersion` 保持唯一。例如，使用 GitHub Actions 的 <code v-pre>${{ github.run_number }}</code>。若透過 `tuist share` 再次上傳相同的二進位檔與建置編號，將會失敗而不會建立重複項目。

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

請參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link> 以了解如何執行已發布的建置版本、存取權限、追蹤軌道以及 README 徽章。

<!-- @snippet: ./_tuist-share -->

接收者可以使用 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 應用程式</.localized_link> 或 <.localized_link href="/guides/features/previews/run/ios">iPhone 應用程式</.localized_link>，無需依賴建置系統整合。iPhone 指南也涵蓋了搭配 Tuist SDK 使用的 <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">應用程式內更新通知</.localized_link>。
