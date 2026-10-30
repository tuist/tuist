---
{
  "title": "Android",
  "titleTemplate": ":title · Bundle 洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Bundle Insights 分析 Android 應用程式套件 (.aab) 及安裝檔 (.apk)。"
}
---
# Android {#bundle-insights-android}

將 `tuist inspect bundle` 指向應用程式套件或可安裝檔案，以分析 Android 套件：

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
> **分析 `.apk` 需要 `aapt2`**，該工具隨附於 Android SDK build tools。設定 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT` 讓 Tuist 能夠找到它，或將 `aapt2` 加入 `PATH`。分析 `.aab` 則無需外部工具。

此命令會將套件上傳至 Tuist，並回傳一個連結，提供詳細概覽，包括內容掃描及模組細分：

![已分析的套件](/images/guides/features/bundle-size/analyzed-bundle.png)

<!-- @snippet: ./_shared -->
