---
{
  "title": "Android",
  "titleTemplate": ":title · Bundle 分析 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Bundle Insights 分析 Android 應用程式套件 (.aab) 與安裝檔 (.apk)。"
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
> **分析 `.apk` 需要 `aapt2`**，此工具隨附於 Android SDK 建置工具中。設定 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT`，讓 Tuist 能夠找到它，或將 `aapt2` 加入 `PATH`。分析 `.aab` 則不需要任何外部工具。

此指令會將套件上傳至 Tuist，並回傳一個連結，提供詳細概覽，包括內容掃描與模組細目：

![已分析的套件](/images/guides/features/bundle-size/analyzed-bundle.png)

<!-- @snippet: ./_shared -->
