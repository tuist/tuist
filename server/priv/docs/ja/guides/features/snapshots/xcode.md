---
{
  "title": "Xcode",
  "titleTemplate": ":title · スナップショット · 機能 · ガイド · Tuist",
  "description": "XcodeプロジェクトのすべてのSwiftUIプレビューをスナップショットとして保存し、Tuistで変更を確認できます。"
}
---
# Xcode スナップショット {#xcode-snapshots}

> [!IMPORTANT]
> **要件**
>
> - アカウントでスナップショットが有効になっている必要があります。現在は招待制です。[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) でアクセスをリクエストしてください。
> - Tuist に <.localized_link href="/guides/get-started/existing-xcode-project">接続されたプロジェクト</.localized_link>。
> - プレビューのレンダリングには iOS 17 または macOS 14 が必要です。

[tuist/snapshots](https://github.com/tuist/snapshots) ライブラリはアプリ内のすべての SwiftUI プレビューを画像としてレンダリングするため、手動でスナップショットテストを書く必要がありません。`tuist xcodebuild test` は実行後に画像をアップロードし、Tuist がそれらを <.localized_link href="/guides/features/snapshots#how-it-works">ベースライン</.localized_link> と比較します。

## セットアップ {#set-up}

1. Xcode で `https://github.com/tuist/snapshots` パッケージをバージョン `0.1.0` から追加します。
2. アプリがホストするユニットテストターゲット（例: `AppSnapshotTests`）を作成し、パッケージの `TuistSnapshotsTesting` プロダクトをリンクします。
3. そのターゲットにテストクラスを追加します。各プレビューが個別のテストになります。

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

4. ターゲットを実行するスキーム（例: `AppSnapshots`）を追加します。このスキーム名がスナップショットセットの名前となります。

## 実行 {#run}

`tuist xcodebuild test` を介してテストを実行します。異なるデバイスでは画像サイズが変わるため、常に同じシミュレーター上使用してください。

```bash
tuist xcodebuild test -scheme AppSnapshots -destination 'platform=iOS Simulator,name=iPhone 17'
```

CI では、テストによってレンダリングされた画像が実行後にアップロードされ、画像に変更がありかつ誰も承認していない場合、コマンドは失敗します。ローカル実行では未コミットの変更がアップロードされてしまうため、何もアップロードしません。

<!-- @snippet: ./_previews-library -->
