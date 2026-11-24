---
{
  "title": "Gradle",
  "titleTemplate": ":title · スナップショット · 機能 · ガイド · Tuist",
  "description": "Tuist Gradle プラグインを使用して、Compose プレビューのスナップショットを毎回取得したり、Paparazzi や Roborazzi が記録した内容をアップロードできます。"
}
---
# Gradle スナップショット {#gradle-snapshots}

> [!IMPORTANT]
> **要件**
>
> - アカウントでスナップショットが有効になっている必要があります。現在は招待制です。[お問い合わせ](mailto:contact@tuist.dev)いただくか、[コミュニティ Slack](https://slack.tuist.dev) でアクセスをリクエストしてください。
> - <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle プラグイン</.localized_link>。
> - スナップショットを取得するモジュールに [Paparazzi](https://github.com/cashapp/paparazzi) または [Roborazzi](https://github.com/takahirom/roborazzi) が含まれていること。

Tuist Gradle プラグインは Paparazzi と Roborazzi が記録した画像をアップロードし、Tuist がそれらを <.localized_link href="/guides/features/snapshots#how-it-works">ベースライン</.localized_link> と比較します。Paparazzi を適用したモジュールでは、プラグインがすべての Compose `@Preview` をレンダリングするテストも生成するため、手動でスナップショットテストを書く必要がありません。

## セットアップ {#set-up}

`settings.gradle.kts` でスナップショットを有効にします。

```kotlin
tuist {
    snapshots {
        enabled = true
        set = "android-phone" // Defaults to the Gradle project's path.
    }
}
```

## 実行 {#run}

CI では、`./gradlew test` がプレビューをレンダリングしてアップロードし、変更があり誰も承認していない場合にビルドが失敗します。ローカル実行では何もアップロードされません。未コミットの変更がアップロードされるのを防ぐためです。CI でアップロードを無効にするには `-Ptuist.snapshots=false` を渡してください。

Paparazzi および Roborazzi の記録タスク（例: `recordPaparazziDebug`）は、スナップショットが有効な場合常にアップロードを行います。

## オプション {#options}

`snapshots` ブロックでは以下のオプションを受け取ります。

- `enabled`: スナップショットをアップロードするかどうか。デフォルトは `false` です。
- `set`: ビルドを比較するセット。デフォルトは Gradle プロジェクトのパスです。
- `directory`: アップロードする画像を含むディレクトリ（Gradle プロジェクトからの相対パス）。デフォルトは、生成されたプレビューテストまたはスナップショットライブラリが書き込む場所です。
- `failOnChanges`: 誰も承認していない変更があった場合にビルドを失敗させるかどうか。デフォルトは `true` です。
- `diffThreshold`: 画像が変更済みと判定される前に許容されるピクセルの割合（0 から 1）。デフォルトは `0` です。
- `previews { generateTests }`: Compose プレビューテストを生成するかどうか。デフォルトは `true` です。
- `previews { packageTrees }`: プレビューを検索するパッケージ。デフォルトは Android ネームスペースです。
- `previews { includePrivatePreviews }`: プライベートな `@Preview` 関数もレンダリングするかどうか。デフォルトは `false` です。
- `previews { theme }`: プレビューのレンダリングに使用する Android テーマ。デフォルトは Paparazzi のテーマです。
