---
{
  "title": "Apple",
  "titleTemplate": ":title · Bundle Insights · 機能 · ガイド · Tuist",
  "description": "Tuist Bundle Insights を使用して、iOS、iPadOS、macOS、watchOS、tvOS のバンドル（.ipa、.xcarchive、.app）を分析します。"
}
---
# Apple {#bundle-insights-apple}

アーカイブ、インストール可能ファイル、またはビルド済みアプリを `tuist inspect bundle` に指定して、Apple バンドルを分析します:

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

macOS でパスではなくアプリ名を指定すると、Tuist は Xcode のビルド成果物からビルド済みの `.app` を解決します（`--derived-data-path` が設定されている場合はそれを尊重）。これは `tuist share` と同じ動作です。

<!-- @snippet: ./_upload-result -->

## App Store Connect との比較 {#app-store-connect}

Tuist は提供されたバンドルをそのまま測定し、[app thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size) は適用しません。報告されるサイズは **universal**（未細分化）バリアントに対応しており、App Store Connect のアプリファイルサイズレポートで「Universal」とラベル付けされた行の値です。デバイスごとのバリアントではありません。

数値は Universal 行と同じ範囲になると予想されますが、同一ではありません:

- **Install size** は Universal のインストールサイズに近い値です。App Store Connect が報告する値はやや高くなります。これは、ファイルシステムのブロック割り当てや Apple 独自の推定など、生のファイルサイズ測定では捕捉できないオンデバイスのオーバーヘッドが含まれているためです。
- **Download size** は Universal のダウンロードサイズより小さくなります。Apple はアップロード後にアプリバイナリを暗号化するため、暗号化データは圧縮効率が低下し、App Store の圧縮済みダウンロードは Tuist が測定する `.ipa` アーカイブよりも大きくなります。これはアップロード後に Apple 側で発生するため、Tuist の数値には反映されません。

App Store Connect のデバイスごとの行はさらに小さくなります。これは、app thinning によって特定のデバイスが必要としない CPU アーキテクチャやアセットバリアントが削除されるためです。Tuist は現在、デバイスごと（細分化済み）のサイズを報告していません。

<!-- @snippet: ./_shared -->
