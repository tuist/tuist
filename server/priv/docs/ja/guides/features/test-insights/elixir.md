---
{
  "title": "Elixirテストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "TuistダッシュボードでElixirプロジェクトのテストを追跡し、テストパフォーマンスを監視します。"
}
---
# Elixirのテストインサイト {#elixir-test-insights}

TuistのHexパッケージは、各テスト実行後にElixirプロジェクトのテスト結果をアップロードし、Tuistダッシュボードでテストのパフォーマンスと不安定なテストを可視化します。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/elixir-project">Elixirを使い始める</.localized_link>を完了する

## テスト実行を報告する {#report-your-test-runs}

共有セットアップによりテスト統合がインストールされます。`mix test`をこれまでと同じ引数、出力、終了コードで使用してください:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuistは実行が完了するとレポートを送信します。追加のテストエイリアスは不要です。

Tuistダッシュボードでテストインサイトにアクセスし、時間経過に伴う変化を確認できます:

![Phoenixアプリケーションのテストダッシュボード](/images/guides/features/elixir/tests-dashboard.png)

## 収集される情報 {#what-is-tracked}

このパッケージはExUnitの結果を収集します。対象には以下が含まれます:
- 個々のテストの合否ステータスと実行時間
- 各テストが属するモジュールと`describe`ブロック
- 各失敗のメッセージと発生箇所
- 複数回の実行にわたる不安定なテストの検出
- ブランチとコミット、およびCI環境ではプロバイダーと実行情報
- CI環境では、チェックアウトの[Git履歴](#git-history)

Doctestも他のテストと同様に報告されます。`--cover`を使用すると、その実行のカバレッジもアップロードされます。<.localized_link href="/guides/features/test-code-coverage/elixir">Elixirのコードカバレッジ</.localized_link>をご覧ください。

> [!NOTE]
> このパッケージは、既存のフォーマッターに加えてExUnitフォーマッターを追加してレポートを送信します。コマンドラインで`--formatter`を指定すると、Mixがフォーマッターのリスト全体を置き換えるため、実行は報告されず、タスクから警告が表示されます。

### Git履歴 {#git-history}

CI環境では、このパッケージはチェックアウトのコミット履歴（コミットSHA、親コミット、コミット日時、実行およびプルリクエストのベースブランチ）もアップロードします。ファイルの内容、コミットメッセージ、著者はアップロードされません。これにより、Tuistはデフォルトブランチにマージされたコミット（例えばマージキューでテストされたもの）を識別できます。パッケージはチェックアウトに既存の履歴を読み取り、ベースブランチがない場合はリモートに対して最新のコミットを問い合わせます（`git ls-remote`）。コードカバレッジ（`--cover`）以外の場合、履歴のフェッチは行いません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git履歴の読み取りやアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに接続せず、チェックアウトのみを読み取ります。 |

## トラブルシューティング {#troubleshooting}

レポート送信はテストの結果を変更しません。レポートを送信できない場合、実行は通常通り終了し、何も出力されません。レポートが送信されない理由を確認するには、`TUIST_DEBUG=1`を設定してください:

```bash
TUIST_DEBUG=1 mix test
```
