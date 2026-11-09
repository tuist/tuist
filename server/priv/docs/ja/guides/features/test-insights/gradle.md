---
{
  "title": "Gradle テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Gradle のテスト分析を追跡し、テストパフォーマンスを監視します。"
}
---
# Gradle テストインサイト {#gradle-test-insights}

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/gradle-project">Gradle プロジェクトを始める</.localized_link>で説明されているように、`dev.tuist` Gradle プラグインが適用されていること。

Tuist の Gradle プラグインは、各テストタスクの実行後にテスト結果を自動的にアップロードし、Tuist ダッシュボード上でテストのパフォーマンスや不安定なテストの状況を可視化します。

プラグインを適用すると、テストインサイトは自動的に収集されます。追加の設定は不要です。

Tuist ダッシュボードでテストインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます：

![テストインサイト付きダッシュボード](/images/guides/features/build-insights/tests-dashboard.png)

## 追跡対象 {#what-is-tracked}

このプラグインは、すべての Gradle `Test` タスクの結果を収集します。これには以下が含まれます：
- 個々のテストケースの合否ステータスと実行時間
- テストスイートおよびクラス構造
- 複数回の実行にわたる不安定なテストの検出

## アップロード動作の設定 {#configure-upload-behavior}

デフォルトでは：
- ローカルビルドの場合、テスト結果はバックグラウンドでアップロードされます。
- CI 実行の場合、短命なエージェントでのテレメトリ損失を防ぐため、テスト結果はフォアグラウンドでアップロードされます。

`settings.gradle.kts` 内の `tuist` ブロックで `uploadInBackground` を使用して、この動作を上書きできます：

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git ヒストリ {#git-history}

CI 環境では、プラグインはテスト実行を報告する際に、チェックアウトのコミットヒストリもアップロードします。これには、コミット SHA、その親コミット、コミット日時、およびその実行とプルリクエストのベースブランチが属していたブランチが含まれます。ファイルの内容、コミットメッセージ、または作者情報はアップロードされません。これは、マージキューでテストされたものなど、どのコミットがデフォルトブランチに取り込まれたかを Tuist に伝えるためのものです。プラグインはチェックアウトが既に持っているヒストリを読み取り、チェックアウトにベースブランチがない場合は、リモートに対して最新のコミットを問い合わせます（`git ls-remote`）。ヒストリのフェッチは行いません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git ヒストリの読み取りやアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに接続せず、チェックアウトのみを読み取ります。 |
