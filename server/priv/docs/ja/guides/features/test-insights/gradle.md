---
{
  "title": "Gradle Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Gradle test analytics in the Tuist dashboard to monitor test performance."
}
---
# Gradle テストインサイト {#gradle-test-insights}

Tuist の Gradle プラグインは、各テストタスクの実行後にテスト結果を自動的にアップロードし、Tuist ダッシュボードで直接テストのパフォーマンスや不安定なテスト（flaky tests）の可視化を提供します。

Tuist Gradle プラグインが適用されると、テストインサイトは自動的に収集されます。初期のプラグイン設定以外に追加の設定は必要ありません。

Tuist ダッシュボードでテストインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます。

![テストインサイトを表示するダッシュボード](/images/guides/features/build-insights/tests-dashboard.png)

## 追跡対象 {#what-is-tracked}

このプラグインは、すべての Gradle `Test` タスクの結果を収集します。これには以下が含まれます。
- 個々のテストケースの合否ステータスと実行時間
- テストスイートおよびクラス構造
- 複数回の実行にわたる不安定なテスト（flaky test）の検出

## アップロード動作の設定 {#configure-upload-behavior}

デフォルトでは：
- ローカルビルドの場合、テスト結果はバックグラウンドでアップロードされます。
- CI 実行の場合、短命のエージェントでのテレメトリ損失を防ぐため、テスト結果はフォアグラウンドでアップロードされます。

`settings.gradle.kts` 内の `tuist` ブロックで `uploadInBackground` を使用して、この動作を上書きできます。

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Git ヒストリー {#git-history}

CI では、プラグインはテスト実行を報告する際に、チェックアウトのコミットヒストリーもアップロードします。これには、コミット SHA、その親コミット、コミット日時、および実行とそのプルリクエストのベースブランチが含まれます。ファイルの内容、コミットメッセージ、または作者はアップロードされません。これは、どのコミットがデフォルトブランチに取り込まれたか（例えば、マージキューによってテストされたもの）を Tuist に伝えるためのものです。プラグインはチェックアウトが既に持っているヒストリーを読み取り、チェックアウトにベースブランチがない場合は、リモートに対して最新のコミットを要求します（`git ls-remote`）。ヒストリーをフェッチすることはありません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git ヒストリーの読み取りまたはアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに接続せず、チェックアウトのみを読み取ります。 |
