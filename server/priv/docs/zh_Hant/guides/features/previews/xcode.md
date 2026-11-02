---
{
  "title": "Xcode 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "分享來自現有 Xcode 專案和 Tuist 產生之專案的應用程式預覽。"
}
---
# Xcode Previews

建置你的應用程式，然後使用 `tuist share` 將其發布至你的 Tuist 專案。請先依照 <.localized_link href="/guides/get-started/existing-xcode-project">現有 Xcode 專案</.localized_link> 或 <.localized_link href="/guides/get-started/generated-xcode-project">產生的專案</.localized_link> 指南來連接你的專案。

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

將 scheme、專案與工作區名稱替換為你自己的名稱。若要分享 Release 建置，請在建置時使用 `-configuration Release`，並在分享時使用 `--configuration Release`。

## 實體裝置

你必須負責使用允許在接收者裝置上安裝的描述檔來簽署裝置建置。請以裝置目的地進行建置，而非使用模擬器 SDK：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

你也可以分享已匯出的 IPA：

```bash
tuist share App.ipa
```

接收者可以在行動裝置上開啟 IPA preview 連結以安裝應用程式。驗證與專案的 preview 可見性設定仍然適用。

## CI 與建置編號

使用你現有的 <.localized_link href="/guides/integrations/continuous-integration">CI 驗證</.localized_link>，並讓 `CFBundleVersion` 在每次新建置時保持唯一。例如，使用 GitHub Actions 的 <code v-pre>{{ github.run_number }}</code>。若透過 `tuist share` 再次上傳相同的二進位檔與建置編號，將會失敗而不會建立重複項目。

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

請參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行 Preview</.localized_link>，了解如何執行已發布的建置、存取權限、tracks 與 README badges。

<!-- @snippet: ./_tuist-share -->

接收者可以獨立於建置系統整合之外，使用 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS app</.localized_link> 或 <.localized_link href="/guides/features/previews/run/ios">iPhone app</.localized_link>。iPhone 指南也涵蓋搭配 Tuist SDK 的 <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">App 內更新通知</.localized_link>。
