---
{
  "title": "Apple",
  "titleTemplate": ":title · Bundle 分析 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Bundle Insights 分析 iOS、iPadOS、macOS、watchOS 同 tvOS bundle（.ipa、.xcarchive、.app）。"
}
---
# Apple {#bundle-insights-apple}

將 `tuist inspect bundle` 指向封存檔、可安裝檔案或已建置的應用程式，以分析 Apple bundle：

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

當你在 macOS 上傳遞應用程式名稱而非路徑時，Tuist 會從 Xcode 的建置產物中解析已建置的 `.app`（如有設定則遵循 `--derived-data-path`），做法與 `tuist share` 相同。

此指令會將 bundle 上傳至 Tuist，並回傳詳細概覽的連結，包括內容掃描與模組細項：

![已分析的 bundle](/images/guides/features/bundle-size/analyzed-bundle.png)

## 與 App Store Connect 比較 {#app-store-connect}

Tuist 會按照你提供的 bundle 精確測量，且不會套用 [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)。回報的大小對應於 **universal**（未精簡）變體——即 App Store Connect 應用程式檔案大小報告中标記為「Universal」的列——而非各裝置變體。

預期數值會與 Universal 列相近，但並非完全相同：

- **安裝大小**接近 Universal 安裝大小。App Store Connect 回報的數值略高，因為它包含裝置端開銷，例如檔案系統區塊配置及 Apple 自身的估算，而原始檔案大小測量無法捕捉這些項目。
- **下載大小**低於 Universal 下載大小。Apple 會在上傳後加密應用程式二進位檔，而加密資料的壓縮效率較低，因此 App Store 的壓縮下載結果會大於 Tuist 測量的 `.ipa` 封存檔。這是在上傳後由 Apple 端發生，因此不會反映在 Tuist 的數值中。

App Store Connect 中各裝置的列更小，因為 app thinning 會移除特定裝置不需要的 CPU 架構與資源變體。Tuist 目前不會回報各裝置（精簡後）的大小。

<!-- @snippet: ./_shared -->
