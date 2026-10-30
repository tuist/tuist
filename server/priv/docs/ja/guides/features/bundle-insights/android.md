---
{
  "title": "Android",
  "titleTemplate": ":title · Bundle Insights · 機能 · ガイド · Tuist",
  "description": "Tuist Bundle Insights を使用して、Android アプリバンドル（.aab）およびインストール可能ファイル（.apk）を分析します。"
}
---
# Android {#bundle-insights-android}

`tuist inspect bundle` をアプリバンドルまたはインストール可能なファイルに向けて、Android バンドルを分析します:

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
> **`.apk` の分析には `aapt2` が必要です**。これは Android SDK ビルドツールに含まれています。Tuist が検出できるよう `ANDROID_HOME` または `ANDROID_SDK_ROOT` を設定するか、`aapt2` を `PATH` に追加してください。`.aab` の分析には外部ツールは不要です。

このコマンドはバンドルを Tuist にアップロードし、コンテンツのスキャンやモジュールの内訳などを含む詳細な概要へのリンクを返します:

![分析されたバンドル](/images/guides/features/bundle-size/analyzed-bundle.png)

<!-- @snippet: ./_shared -->
