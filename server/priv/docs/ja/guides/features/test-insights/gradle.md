---
{
  "title": "Gradle テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Gradle のテスト分析を追跡し、テストパフォーマンスを監視します。"
}
---
# Gradle テストのインサイト {#gradle-test-insights}

> [!IMPORTANT]
> **要件**
>
> - `dev.tuist` Gradle プラグインが適用されていること（詳細は <.localized_link href="/guides/get-started/gradle-project">Gradle プロジェクトを始める</.localized_link> を参照）。

Tuist の Gradle プラグインは、各テストタスクの実行後にテスト結果を自動的にアップロードし、Tuist ダッシュボード上でテストのパフォーマンスや不安定なテストを可視化します。

プラグインを適用すると、テストのインサイトは自動的に収集されます。追加の設定は不要です。

Tuist ダッシュボードでテストのインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます：

![テストのインサイトを表示するダッシュボード](/images/guides/features/build-insights/tests-dashboard.png)

## 追跡対象 {#what-is-tracked}

このプラグインは、すべての Gradle `Test` タスクの結果を収集します。対象には以下が含まれます：
- 個々のテストケースの合否ステータスと実行時間
- テストスイートおよびクラス構造
- 複数回の実行にわたる不安定なテストの検出

<.localized_link href="/guides/features/test-code-coverage/gradle">コードカバレッジ</.localized_link> を有効にすると、テストが実行したコードもアップロードされます。

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

### Git ヒストリー {#git-history}

CI 環境では、プラグインはテスト実行を報告する際に、チェックアウトのコミット履歴もアップロードします。これには、コミット SHA、その親コミット、コミット日時、および実行とそのプルリクエストのベースブランチが属していたブランチが含まれます。ファイルの内容、コミットメッセージ、著者はアップロードされません。これにより、Tuist はどのコミットがデフォルトブランチに取り込まれたか（例えば、マージキューによってテストされたコミット）を把握できます。プラグインはチェックアウトが既に持っている履歴を読み取り、チェックアウトにベースブランチがない場合は、リモートに対して最新のコミットを問い合わせます（`git ls-remote`）。コードカバレッジ以外の場合、履歴の取得は行いません。コードカバレッジを使用する場合、ファイルの内容なしで浅いチェックアウトを深化させ、プルリクエストが分岐した地点を特定し、Tuist が既に持っているコミットに到達できるようにします。これにより、親コミットのないコミットがアップロードされることはありません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git 履歴の読み取りまたはアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに接続せず、チェックアウトのみを読み取ります。 |
