---
{
  "title": "Android",
  "titleTemplate": ":title · Bundle insights · 機能 · ガイド · Tuist",
  "description": "Tuist Bundle Insights で Android アプリバンドル (.aab) とインストール可能ファイル (.apk) を分析します。"
}
---
# Android {#bundle-insights-android}

`tuist inspect bundle` をアプリバンドルまたはインストール可能なファイルに向けて、Android バンドルを解析します:

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
> **`.apk` の解析には `aapt2` が必要**です。これは Android SDK ビルドツールに含まれています。`ANDROID_HOME` または `ANDROID_SDK_ROOT` を設定して Tuist が検出できるようにするか、`aapt2` を `PATH` に追加してください。`.aab` の解析には外部ツールは不要です。

<!-- @snippet: ./_upload-result -->

<!-- @snippet: ./_shared -->
