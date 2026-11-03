---
{
  "title": "Elixirテストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "TuistダッシュボードでElixirプロジェクトのテストを追跡し、テストパフォーマンスを監視します。"
}
---
# Elixir テストのインサイト {#elixir-test-insights}

Tuist の Hex パッケージは、各テスト実行後に Elixir プロジェクトのテスト結果をアップロードし、Tuist ダッシュボードでテストのパフォーマンスと不安定なテストを可視化します。

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/get-started/elixir-project">Elixir での始め方</.localized_link> を完了する

## テスト実行を報告する {#report-your-test-runs}

共有セットアップによりテスト統合がインストールされます。`mix test` は引き続き同じ引数、出力、終了コードで使用してください:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist は実行が完了した時点で報告します。追加のテストエイリアスは不要です。

Tuist ダッシュボードでテストのインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます:

![Phoenix アプリケーションのテストダッシュボード](/images/guides/features/elixir/tests-dashboard.png)

## 追跡対象 {#what-is-tracked}

このパッケージは ExUnit の結果を収集します。対象には以下が含まれます:
- 個々のテストの合否ステータスと実行時間
- 各テストが属するモジュールおよび `describe` ブロック
- 各失敗のメッセージと場所
- 複数回の実行にわたる不安定なテストの検出
- ブランチとコミット、および継続的インテグレーションではプロバイダーと実行
- 継続的インテグレーションでは、チェックアウトの [Git 履歴](#git-history)

Doctest も他のテストと同様に報告されます。`--cover` を使用すると、実行の行カバレッジもアップロードされます。<.localized_link href="/guides/features/test-code-coverage/elixir">Elixir のコードカバレッジ</.localized_link> を参照してください。

> [!NOTE]
> このパッケージは、既存のフォーマッターに加えて ExUnit フォーマッターを追加して報告を行います。コマンドラインで `--formatter` を指定すると、Mix がフォーマッターのリスト全体を置き換えるため、実行は報告されず、タスクから警告が表示されます。

### Git 履歴 {#git-history}

継続的インテグレーションでは、パッケージはチェックアウトのコミット履歴（コミット SHA、その親コミット、コミット日時、および実行とそのプルリクエストのベースブランチ）もアップロードします。ファイルの内容、コミットメッセージ、または作者はアップロードされません。これにより、Tuist はどのコミットがデフォルトブランチに取り込まれたか（たとえばマージキューでテストされたコミット）を把握できます。パッケージはチェックアウトに既に存在する履歴を読み取り、チェックアウトにベースブランチがない場合はリモートに対して最新のコミットを問い合わせます（`git ls-remote`）。コードカバレッジ（`--cover`）以外の場合、履歴の取得は行いません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git 履歴の読み取りおよびアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに接続せず、チェックアウトのみを読み取ります。 |

## トラブルシューティング {#troubleshooting}

報告はテストの結果を変更しません。報告を送信できない場合、実行は通常どおり終了し、何も出力されません。報告が送信されなかった理由を確認するには、`TUIST_DEBUG=1` を設定してください:

```bash
TUIST_DEBUG=1 mix test
```
