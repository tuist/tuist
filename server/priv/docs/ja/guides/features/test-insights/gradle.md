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
> - `dev.tuist` Gradle プラグインが適用されていること。詳細は <.localized_link href="/guides/get-started/gradle-project">Gradle プロジェクトを始める</.localized_link> を参照してください。

Tuist の Gradle プラグインは、各テストタスクの実行後にテスト結果を自動的にアップロードし、Tuist ダッシュボード上でテストのパフォーマンスや不安定なテストを可視化します。

プラグインを適用すると、テストインサイトは自動的に収集されます。追加の設定は不要です。

Tuist ダッシュボードでテストインサイトにアクセスし、時間経過に伴う変化を確認できます。

![テストインサイトを表示するダッシュボード](/images/guides/features/build-insights/tests-dashboard.png)

## 収集対象 {#what-is-tracked}

このプラグインは、すべての Gradle `Test` タスクから結果を収集します。対象には以下が含まれます。
- 個々のテストケースの合否ステータスと実行時間
- テストスイートおよびクラスの構造
- 複数回の実行にわたる不安定なテストの検出

<.localized_link href="/guides/features/test-code-coverage/gradle">コードカバレッジ</.localized_link> を有効にすると、テストが実行したコードも合わせてアップロードされます。

## アップロード動作の設定 {#configure-upload-behavior}

デフォルトでは:
- ローカルビルドの場合、テスト結果はバックグラウンドでアップロードされます。
- CI 実行の場合、短命なエージェントでのテレメトリ損失を防ぐため、テスト結果はフォアグラウンドでアップロードされます。

`settings.gradle.kts` 内の `tuist` ブロックで `uploadInBackground` を使用して、この動作を上書きできます。

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git ヒストリー {#git-history}

CI 上では、プラグインはテスト実行を報告する際に、チェックアウトのコミット履歴もアップロードします。これには、コミット SHA、その親コミット、コミット日時、および実行とそのプルリクエストのベースブランチが含まれます。ファイルの内容、コミットメッセージ、作成者はアップロードされません。これにより、Tuist はどのコミットがデフォルトブランチに取り込まれたか（例えばマージキューによってテストされたコミット）を把握できます。プラグインはチェックアウトが既に持っている履歴を読み取り、チェックアウトにベースブランチがない場合は、リモートに対して最新のコミットを問い合わせます（`git ls-remote`）。履歴のフェッチは行いません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git ヒストリーの読み取りおよびアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに接続せず、チェックアウトのみを読み取ります。 |
