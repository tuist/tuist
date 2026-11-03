---
{
  "title": "Xcode 預覽",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "分享來自現有 Xcode 專案同 Tuist 生成專案嘅應用程式預覽。"
}
---
# Xcode 預覽

編譯你的應用程式，然後使用 `tuist share` 將其發佈到你的 Tuist 專案。首先參照 <.localized_link href="/guides/get-started/existing-xcode-project">現有 Xcode 專案</.localized_link> 或 <.localized_link href="/guides/get-started/generated-xcode-project">生成專案</.localized_link> 指南來連接你的專案。

## 編譯與分享

對於由 Tuist 生成的專案：

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

對於現有的 Xcode 專案：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

將 scheme、專案和 workspace 名稱替換為你自己的。若要分享 Release 編譯版本，請在編譯時使用 `-configuration Release`，並在分享時使用 `--configuration Release`。

## 實體裝置

你必須負責使用允許在接收者裝置上安裝的描述檔來簽署裝置編譯版本。請使用裝置目標而非模擬器 SDK 進行編譯：

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

你也可以分享已匯出的 IPA：

```bash
tuist share App.ipa
```

接收者可以在其移動裝置上開啟 IPA 預覽連結以安裝應用程式。驗證及專案的預覽可見性設定仍然適用。

## CI 與編譯號碼

使用你現有的 <.localized_link href="/guides/integrations/continuous-integration">CI 驗證</.localized_link>，並確保每個新編譯版本的 `CFBundleVersion` 都是獨一無二的。例如，使用 GitHub Actions 的 <code v-pre>{{ github.run_number }}</code>。透過 `tuist share` 再次上傳相同的二進位檔案和編譯號碼將會失敗，而不會建立重複項目。

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

請參閱 <.localized_link href="/guides/features/previews#run-a-preview">執行預覽</.localized_link> 以了解如何執行已發佈的編譯版本、存取權限、軌道以及 README 徽章。

<!-- @snippet: ./_tuist-share -->

接收者可以獨立於編譯系統整合之外，使用 <.localized_link href="/guides/features/previews/run/macos">Tuist macOS 應用程式</.localized_link> 或 <.localized_link href="/guides/features/previews/run/ios">iPhone 應用程式</.localized_link>。iPhone 指南還涵蓋了使用 Tuist SDK 的 <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">應用程式內更新通知</.localized_link>。
