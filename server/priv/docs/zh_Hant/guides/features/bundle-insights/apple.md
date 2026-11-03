---
{
  "title": "Apple",
  "titleTemplate": ":title · Bundle 洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Bundle Insights 分析 iOS、iPadOS、macOS、watchOS 和 tvOS 套件（.ipa、.xcarchive、.app）。"
}
---
# Apple {#bundle-insights-apple}

將 `tuist inspect bundle` 指向封存檔、可安裝套件或已建置的 App，以分析 Apple Bundle：

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

在 macOS 上，當你傳入 App 名稱而非路徑時，Tuist 會從 Xcode 的建置產物中解析已建置的 `.app`（若已設定則遵循 `--derived-data-path`），其運作方式與 `tuist share` 相同。

此指令會將 Bundle 上傳至 Tuist，並回傳詳細概覽的連結，包括內容掃描與模組細分：

![已分析的 Bundle](/images/guides/features/bundle-size/analyzed-bundle.png)

## 與 App Store Connect 比較 {#app-store-connect}

Tuist 會依照你提供的 Bundle 精確測量，且不會套用 [App Thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)。回報的大小對應於 **通用**（未精簡）版本——即 App Store Connect 的 App 檔案大小報告中標示為「Universal」的那一列——而非各裝置專屬的版本。

預期數值會落在 Universal 列的相近範圍，但不會完全相同：

- **安裝大小**接近 Universal 的安裝大小。App Store Connect 回報的數值略高，因為它包含裝置上的額外開銷，例如檔案系統區塊配置與 Apple 自身的估算，而原始檔案大小測量無法捕捉這些項目。
- **下載大小**低於 Universal 的下載大小。Apple 在上傳後會對 App 二進位檔進行加密，而加密資料的壓縮效率較低，因此 App Store 的壓縮下載結果會大於 Tuist 測量的 `.ipa` 封存檔。這是在上傳後由 Apple 端處理，因此不會反映在 Tuist 的數值中。

App Store Connect 中各裝置專屬的列數值更小，因為 App Thinning 會移除特定裝置不需要的 CPU 架構與資源變體。Tuist 目前不會回報各裝置（精簡後）的大小。

<!-- @snippet: ./_shared -->
