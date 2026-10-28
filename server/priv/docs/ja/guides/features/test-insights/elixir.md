---
{
  "title": "Elixir Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the tests of your Elixir project in the Tuist dashboard to monitor test performance."
}
---
# Elixirテストのインサイト {#elixir-test-insights}

TuistのHexパッケージは、各テスト実行後にElixirプロジェクトのテスト結果をアップロードし、Tuistダッシュボードで直接テストのパフォーマンスやflakyなテストを確認できるようにします。

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/get-started/elixir-project">Elixirをはじめよう</.localized_link>を完了してください

## テスト実行を報告する {#report-your-test-runs}

共有セットアップによりテスト統合がインストールされます。`mix test`をこれまでと同じ引数、出力、終了コードで使用し続けてください:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuistは実行が完了した時点でレポートを送信するため、追加のテストエイリアスは不要です。

Tuistダッシュボードでテストのインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます:

![Phoenixアプリケーションのテストダッシュボード](/images/guides/features/elixir/tests-dashboard.png)

## 追跡対象 {#what-is-tracked}

このパッケージはExUnitの結果を収集します。対象には以下が含まれます:
- 個々のテストの合否ステータスと実行時間
- 各テストが属するモジュールおよび`describe`ブロック
- 各失敗のメッセージと場所
- 複数回の実行にわたるflakyなテストの検出
- ブランチとコミット、および継続的インテグレーションではプロバイダーと実行
- 継続的インテグレーションでは、チェックアウトの[Git履歴](#git-history)

Doctestも他のテストと同様に報告されます。

> [!NOTE]
> このパッケージは、すでに使用しているフォーマッターに加えてExUnitフォーマッターを追加してレポートを送信します。コマンドラインで`--formatter`を指定すると、Mixがリスト全体を置き換えるため、実行は報告されず、タスクから警告が表示されます。

### Git履歴 {#git-history}

継続的インテグレーションでは、このパッケージはチェックアウトのコミット履歴（コミットSHA、その親コミット、コミット日時、および実行とそのプルリクエストのベースブランチ）もアップロードします。ファイルの内容、コミットメッセージ、または作者はアップロードされません。これにより、Tuistはどのコミットがデフォルトブランチに取り込まれたか（例えばマージキューでテストされたもの）を把握できます。パッケージはチェックアウトに既に存在する履歴を読み取り、チェックアウトにベースブランチがない場合はリモートに対して最新のコミットを問い合わせます（`git ls-remote`）。コードカバレッジ（`--cover`）以外では、履歴を取得しません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git履歴の読み取りやアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに接続せず、チェックアウトのみを読み取ります。 |

## トラブルシューティング {#troubleshooting}

レポート送信はテストの結果を変更しません。レポートを送信できない場合、実行は通常通り終了し、何も出力されません。レポートが送信されなかった理由を確認するには、`TUIST_DEBUG=1`を設定してください:

```bash
TUIST_DEBUG=1 mix test
```
