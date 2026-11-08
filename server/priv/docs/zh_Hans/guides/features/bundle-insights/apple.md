---
{
  "title": "Apple",
  "titleTemplate": ":title · 包分析洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Bundle Insights 分析 iOS、iPadOS、macOS、watchOS 和 tvOS 包（.ipa、.xcarchive、.app）。"
}
---
# Apple {#bundle-insights-apple}

通过将 `tuist inspect bundle` 指向归档文件、可安装文件或已构建的应用来分析 Apple 应用包：

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

在 macOS 上，当你传递应用名称而非路径时，Tuist 会从 Xcode 的构建产物中解析已构建的 `.app`（如果设置了 `--derived-data-path` 则会遵循该设置），这与 `tuist share` 的工作方式相同。

<!-- @snippet: ./_upload-result -->

## 与 App Store Connect 对比 {#app-store-connect}

Tuist 会精确测量你提供的应用包，且不应用 [App Thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)。报告的大小对应于 **通用**（未精简）变体——即 App Store Connect 应用文件大小报告中标记为“Universal”的行——而非针对特定设备的变体。

预计数值与 Universal 行处于同一范围，但并不完全相同：

- **安装大小**接近 Universal 安装大小。App Store Connect 报告的数值略高，因为它包含了设备上的开销，例如文件系统块分配和 Apple 自身的估算，而原始文件大小测量无法捕捉这些因素。
- **下载大小**低于 Universal 下载大小。Apple 会在上传后对应用二进制文件进行加密，而加密数据的压缩效率较低，因此 App Store 的压缩下载文件会比 Tuist 测量的 `.ipa` 归档文件更大。这种情况发生在上传后的 Apple 端，因此不会反映在 Tuist 的数值中。

App Store Connect 中针对特定设备的行数值更小，因为 App Thinning 会移除特定设备不需要的 CPU 架构和资源变体。Tuist 目前不提供针对特定设备（精简后）的大小报告。

<!-- @snippet: ./_shared -->
