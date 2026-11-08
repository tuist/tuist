---
{
  "title": "Apple",
  "titleTemplate": ":title · 套裝分析 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Bundle Insights 分析 iOS、iPadOS、macOS、watchOS 和 tvOS 套裝（.ipa、.xcarchive、.app）。"
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

在 macOS 上，當你傳入應用程式名稱而非路徑時，Tuist 會從 Xcode 的建置產物中解析已建置的 `.app`（若已設定則遵循 `--derived-data-path`），其行為與 `tuist share` 相同。

<!-- @snippet: ./_upload-result -->

## 與 App Store Connect 比較 {#app-store-connect}

Tuist 會精確測量你提供的套件，且不會套用 [app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)。回報的大小對應於 **universal**（未精簡）變體——即 App Store Connect 應用程式檔案大小報告中标記為「Universal」的列——而非各裝置變體。

預期數值會與 Universal 列落在相同範圍，但不會完全相同：

- **Install size** 接近 Universal 安裝大小。App Store Connect 回報的數值略高，因為它包含了裝置端額外負擔，例如檔案系統區塊配置與 Apple 自身的估算，這些是原始檔案大小測量無法捕捉的。
- **Download size** 低於 Universal 下載大小。Apple 在上傳後會對應用程式二進位檔進行加密，而加密資料的壓縮效率較低，因此 App Store 的壓縮下載結果會大於 Tuist 測量的 `.ipa` 歸檔檔案。這是在上傳後由 Apple 端處理，因此不會反映在 Tuist 的數值中。

App Store Connect 中各裝置的列數值更小，因為 app thinning 會移除特定裝置不需要的 CPU 架構與資源變體。Tuist 目前尚未回報各裝置（精簡後）的大小。

<!-- @snippet: ./_shared -->
