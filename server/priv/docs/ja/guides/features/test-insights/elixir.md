---
{
  "title": "Elixir テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで Elixir プロジェクトのテストを追跡し、テストのパフォーマンスを監視します。"
}
---
# Elixirテストのインサイト {#elixir-test-insights}

TuistのHexパッケージは、各テスト実行後にElixirプロジェクトのテスト結果をアップロードし、Tuistダッシュボード上でテストのパフォーマンスや不安定なテストを可視化します。

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/get-started/elixir-project">Elixir入門</.localized_link>を完了する

## テスト実行をレポートする {#report-your-test-runs}

共有セットアップによりテスト統合がインストールされます。`mix test`を引き続き使用でき、引数、出力、終了コードは同じです:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuistは実行が完了するとレポートを送信するため、追加のテストエイリアスは不要です。

Tuistダッシュボードでテストのインサイトにアクセスし、時間経過とともにどのように変化するかを確認できます:

![Phoenixアプリケーションのテストダッシュボード](/images/guides/features/elixir/tests-dashboard.png)

## 追跡対象 {#what-is-tracked}

このパッケージはExUnitの結果を収集し、以下を含みます:
- 個々のテストの合否ステータスと所要時間
- 各テストが属するモジュールおよび`describe`ブロック
- 各失敗のメッセージと場所
- 複数回の実行にわたる不安定なテストの検出
- ブランチとコミット、継続的インテグレーションではプロバイダーと実行
- 継続的インテグレーションでは、チェックアウトの[Git履歴](#git-history)

Doctestは他のテストと同様にレポートされます。`--cover`を使用すると、実行の行カバレッジもアップロードされます:<.localized_link href="/guides/features/test-code-coverage/elixir">Elixirコードカバレッジ</.localized_link>をご覧ください。

> [!NOTE]
> このパッケージは、すでに使用しているフォーマッターに加えてExUnitフォーマッターを追加してレポートを行います。コマンドラインで`--formatter`を指定すると、Mixがリスト全体を置き換えるため、実行はレポートされず、タスクから警告が表示されます。

### Git履歴 {#git-history}

継続的インテグレーションでは、このパッケージはチェックアウトのコミット履歴（コミットSHA、親コミット、コミット日時、実行およびそのプルリクエストのベースブランチ）もアップロードします。ファイルの内容、コミットメッセージ、著者はアップロードされません。これにより、Tuistはどのコミットがデフォルトブランチにマージされたか（例えばマージキューでテストされたコミット）を把握できます。パッケージはチェックアウトに既に存在する履歴を読み取り、チェックアウトにベースブランチがない場合はリモートに対して最新のコミットを要求します（`git ls-remote`）。コードカバレッジ（`--cover`）以外の場合、履歴は取得しません。

| 変数 | 効果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Git履歴の読み取りまたはアップロードを行いません。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | リモートに接続せず、チェックアウトのみを読み取ります。 |

## トラブルシューティング {#troubleshooting}

レポート送信はテストの結果に影響しません。レポートを送信できない場合、実行は通常通り終了し、何も出力されません。レポートが送信されなかった理由を確認するには、`TUIST_DEBUG=1`を設定してください:

```bash
TUIST_DEBUG=1 mix test
```
