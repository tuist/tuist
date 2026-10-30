---
{
  "title": "Apple",
  "titleTemplate": ":title · Bundle 洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Bundle Insights 分析 iOS、iPadOS、macOS、watchOS 同 tvOS bundle（.ipa、.xcarchive、.app）。"
}
---
# Apple {#bundle-insights-apple}

將 `tuist inspect bundle` 指向歸檔檔案、可安裝套件或已建置的應用程式，以分析 Apple 套件：

::: code-group
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
```bash [Analyze by app name]
tuist inspect bundle App --platforms ios --configuration Debug
```
<!-- -->
:::

當你在 macOS 上傳遞應用程式名稱而非路徑時，Tuist 會從 Xcode 的建置產物中解析已建置的 `.app`（若設定了 `--derived-data-path` 則會遵循），方式與 `tuist share` 相同。

此指令會將套件上傳至 Tuist，並回傳詳細概覽的連結，包括內容掃描和模組細分：

![已分析的套件](/images/guides/features/bundle-size/analyzed-bundle.png)

## 與 App Store Connect 比較 {#app-store-connect}

Tuist 會按照你提供的樣子精確測量套件，不會套用 [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)。回報的大小對應於 **universal**（未精簡）變體——即 App Store Connect 應用程式檔案大小報告中标記為「Universal」的那一列——而非各裝置變體。

預期數值會與 Universal 列處於相同範圍，但不會完全相同：

- **安裝大小**接近 Universal 安裝大小。App Store Connect 回報的數值略高，因為它包含裝置端開銷，例如檔案系統區塊配置和 Apple 自身的估算，而原始檔案大小測量無法捕捉這些。
- **下載大小**低於 Universal 下載大小。Apple 在上傳後會對應用程式二進位檔進行加密，而加密資料的壓縮效率較低，因此 App Store 的壓縮下載結果會比 Tuist 測量的 `.ipa` 歸檔檔案更大。這發生在上傳後的 Apple 端，因此不會反映在 Tuist 的數值中。

App Store Connect 中各裝置的列更小，因為 app thinning 會移除特定裝置不需要的 CPU 架構和資源變體。Tuist 目前不會回報各裝置（精簡後）的大小。

<!-- @snippet: ./_shared -->
