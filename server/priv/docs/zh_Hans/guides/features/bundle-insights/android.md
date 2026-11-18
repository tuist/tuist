---
{
  "title": "Android",
  "titleTemplate": ":title · Bundle insights · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Bundle Insights 分析 Android 应用包 (.aab) 和可安装文件 (.apk)。"
}
---
# Android {#bundle-insights-android}

通过将 `tuist inspect bundle` 指向应用包或可安装文件来分析 Android 包：

::: code-group
```bash [Analyze an .aab (recommended)]
tuist inspect bundle App.aab
```
```bash [Analyze an .apk]
tuist inspect bundle App.apk
```
<!-- -->
:::

> [!NOTE]
> **分析 `.apk` 需要 `aapt2`**，该工具随附于 Android SDK 构建工具中。设置 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT` 以便 Tuist 能够找到它，或者将 `aapt2` 添加到 `PATH` 中。分析 `.aab` 不需要外部工具。

<!-- @snippet: ./_upload-result -->

<!-- @snippet: ./_shared -->
