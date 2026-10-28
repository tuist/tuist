---
{
  "title": "Elixir Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the tests of your Elixir project in the Tuist dashboard to monitor test performance."
}
---
# Elixir テストインサイト {#elixir-test-insights}

Tuist の Hex パッケージは、各テスト実行後に Elixir プロジェクトのテスト結果をアップロードし、Tuist ダッシュボードでテストのパフォーマンスや flaky なテストを可視化します。

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/get-started/elixir-project">Elixir を使い始める</.localized_link>を完了してください

## テスト実行を報告する {#report-your-test-runs}

共有セットアップによりテスト統合がインストールされます。`mix test`をこれまでと同じ引数、出力、終了コードで使用し続けてください：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist は実行が完了した時点でレポートを送信するため、追加のテストエイリアスは不要です。

Tuist ダッシュボードでテストインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます：

![Phoenix アプリケーションのテストダッシュボード](/images/guides/features/elixir/tests-dashboard.png)

## 追跡対象 {#what-is-tracked}

このパッケージは ExUnit の結果を収集します。含まれる項目：
- 個々のテストの合否ステータスと実行時間
- 各テストが属するモジュールおよび `describe` ブロック
- 各失敗のメッセージと場所
- 複数回の実行にわたる flaky なテストの検出
- ブランチとコミット、および継続的インテグレーションではプロバイダーと実行
- 継続的インテグレーションでは、チェックアウトの [Git 履歴](#git-history)

Doctest は他のテストと同様に報告されます。`--cover`を使用すると、実行の行カバレッジもアップロードされます：<.localized_link href="/guides/features/test-code-coverage/elixir">Elixir コードカバレッジ</.localized_link>をご覧ください。

> [!NOTE]
> このパッケージは、すでに使用しているフォーマッターに加えて ExUnit フォーマッターを追加することでレポートを行います。コマンドラインで `--formatter`を指定すると、Mix がリスト全体を置き換えるため、実行は報告されず、タスクから警告が表示されます。

### Git 履歴 {#git-history}

継続的インテグレーションでは、このパッケージはチェックアウトのコミット履歴（コミット SHA、その親コミット、コミット日時、および実行とそのプルリクエストのベースブランチ）もアップロードします。ファイルの内容、コミットメッセージ、または作者はアップロードされません。これにより、Tuist はどのコミットがデフォルトブランチにマージされたか（たとえばマージキューでテストされたコミット）を把握できます。パッケージはチェックアウトにすでに存在する履歴を読み取り、チェックアウトにベースブランチがない場合は、リモートに対して最新のコミットを要求します（`git ls-remote`）。コードカバレッジ（`--cover`）以外の場合、履歴は取得しません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git 履歴の読み取りまたはアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに接続せず、チェックアウトのみを読み取ります。 |

## トラブルシューティング {#troubleshooting}

レポート送信はテストの結果を変更しません：レポートを送信できない場合、実行は通常通り終了し、何も出力されません。レポートが送信されなかった理由を確認するには、`TUIST_DEBUG=1`を設定してください：

```bash
TUIST_DEBUG=1 mix test
```
