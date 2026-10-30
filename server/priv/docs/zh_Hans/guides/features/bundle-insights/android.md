---
{
  "title": "Android",
  "titleTemplate": ":title · Bundle 洞察 · 功能 · 指南 · Tuist",
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
> **分析 `.apk` 需要 `aapt2`**，它随 Android SDK 构建工具一起提供。设置 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT` 以便 Tuist 能够找到它，或者将 `aapt2` 添加到 `PATH`。分析 `.aab` 不需要外部工具。

该命令会将包上传到 Tuist，并返回一个链接，其中包含详细概览，包括内容扫描和模块分解：

![已分析的包](/images/guides/features/bundle-size/analyzed-bundle.png)

<!-- @snippet: ./_shared -->
