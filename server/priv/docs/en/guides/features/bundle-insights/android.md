---
{
  "title": "Android",
  "titleTemplate": ":title · Bundle insights · Features · Guides · Tuist",
  "description": "Analyze Android app bundles (.aab) and installables (.apk) with Tuist Bundle Insights."
}
---
# Android {#bundle-insights-android}

Analyze an Android bundle by pointing `tuist inspect bundle` at an app bundle or an installable:

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
> **Analyzing an `.apk` requires `aapt2`**, which ships with the Android SDK build tools. Set `ANDROID_HOME` or `ANDROID_SDK_ROOT` so Tuist can find it, or put `aapt2` on `PATH`. Analyzing an `.aab` needs no external tools.

<!-- @snippet: ./_upload-result -->

<!-- @snippet: ./_shared -->

