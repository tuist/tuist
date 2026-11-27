---
{
  "title": "Apple",
  "titleTemplate": ":title · Bundle Insights · 機能 · ガイド · Tuist",
  "description": "Tuist Bundle Insights を使用して、iOS、iPadOS、macOS、watchOS、tvOS のバンドル（.ipa、.xcarchive、.app）を分析します。"
}
---
# Apple {#bundle-insights-apple}

アーカイブ、インストール可能ファイル、またはビルド済みアプリを `tuist inspect bundle` に指定して、Apple バンドルを解析します:

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

macOS でパスではなくアプリ名を渡すと、Tuist は Xcode のビルド成果物からビルド済みの `.app` を解決します（`--derived-data-path` が設定されている場合はそれを尊重）。これは `tuist share` と同じ動作です。

<!-- @snippet: ./_upload-result -->

## App Store Connect との比較 {#app-store-connect}

Tuist は提供されたバンドルをそのまま測定し、[App Thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size) は適用しません。報告されるサイズは **Universal**（未 Thin）バリアントに対応します。これは App Store Connect のアプリファイルサイズレポートで「Universal」とラベル付けされた行であり、デバイス別バリアントではありません。

数値は Universal 行と同程度の範囲になると予想されますが、完全に一致するわけではありません:

- **インストールサイズ** は Universal のインストールサイズに近い値になります。App Store Connect では、ファイルシステムのブロック割り当てや Apple 独自の推定など、生のファイルサイズ測定では捉えられないデバイス上のオーバーヘッドが含まれるため、わずかに高い値が報告されます。
- **ダウンロードサイズ** は Universal のダウンロードサイズより小さくなります。Apple はアップロード後にアプリバイナリを暗号化するため、暗号化されたデータは圧縮効率が低下し、App Store の圧縮済みダウンロードは Tuist が測定する `.ipa` アーカイブよりも大きくなります。これはアップロード後に Apple 側で発生するため、Tuist の数値には反映されません。

App Store Connect のデバイス別行はさらに小さくなります。これは、App Thinning によって特定のデバイスが必要としない CPU アーキテクチャやアセットバリアントが削除されるためです。Tuist は現在、デバイス別（Thin 済み）サイズを報告していません。

<!-- @snippet: ./_shared -->
