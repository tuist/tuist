---
{
  "title": "Rust テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで、Rust の doctest を含む Cargo テストの結果を追跡します。"
}
---
# Rust テストのインサイト {#rust-test-insights}

Tuist は `cargo test` から個々のテスト結果を報告します。ユニットテスト、統合テスト、ドキュメントテストが含まれます。Rust の依存関係や追加のテストランナーは不要です。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust プロジェクトのセットアップ</.localized_link>に従ってください。

## テスト実行を報告する {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

mise Cargo ラッパーを設定すれば、引き続き `cargo test` と入力できます。Cargo は通常どおり引数、出力、終了コードを使用してテストをコンパイルおよび実行します。報告の失敗がテストの結果に影響することはありません。

通常どおりパッケージを選択したり、テストをフィルタリングできます。

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist が追跡する情報 {#what-is-tracked}

- 完了したテストスイートからの合格、不合格、無視されたテスト。
- ユニットテスト、統合テスト、ドキュメントテスト。
- スイート全体の所要時間。
- 利用可能なブランチ、コミット、CI、およびランナーのメタデータ。

フィルタリングされたテストや失敗後に実行されなかったテストは、合格として報告されることはありません。結果はダッシュボードの **テスト** に表示されます。

## パッケージ、モジュール、テストケース {#test-hierarchy}

Tuist は Cargo パッケージとターゲットごとに結果をグループ化します。Rust モジュールパスは、ターゲット内の個々のテストをグループ化します。

| ダッシュボードラベル | Rust での意味 | 例 |
| --- | --- | --- |
| モジュール | Cargo パッケージとターゲット | `store::api` |
| テストスイート | Rust モジュールパス | `api::authentication` |
| テストケース | 個々のテスト | `rejects_invalid_token` |

ドキュメントテストは `store::doctest/store` のような別のモジュールを使用します。名前にはソースの場所が含まれるため、例を移動するとその識別子が変更される可能性があります。

## ドキュメントテストと所要時間 {#cargo-test}

ドキュメントテストは通常のテストコマンドで実行され、`compile_fail`、`should_panic`、`no_run` の例が含まれます。ドキュメントテストのみを実行するには:

```sh
tuist cargo test --doc
```

安定版の libtest はスイート全体の時間を報告しますが、個々のテストの所要時間は報告しません。利用できないタイミング情報はケースごとの所要時間の履歴や分析から除外されますが、テストの結果は信頼性と実行回数に依然として反映されます。

## 報告の制限 {#reporting-limits}

個々の結果は Cargo/libtest のデフォルト出力から収集されます。`--no-run`、`--list`、quiet または Cargo-verbose 出力、代替フォーマット、またはキャプチャされていないテスト出力を使用するコマンドは、個々のテスト報告なしで通常どおり実行されます。カスタムハーネス、不完全なサマリー、曖昧なターゲット属性、および大きすぎるレポートはアップロードされません。

ワークスペースのパッケージに同名の統合ターゲットがある場合は、`-p <package>` で 1 つを選択してください。報告は正確なワークスペースパッケージ名をサポートします。依存パッケージ、バージョン修飾セレクター、およびグロブは通常どおり実行されますが、報告されません。絶対ドキュメントテストパスは、チェックアウトパスがテストの識別子に含まれないように省略されます。

Tuist は結果を収集しながら出力をストリーミングします。これにより、自動カラー検出に影響を与える可能性があります。Cargo 終了後も出力パイプを開いたままにするバックグラウンドプロセスがあると、レポートが省略される原因になりますが、Cargo の終了ステータスは変更されません。

## 信頼性と選択 {#reliability-and-selection}

<.localized_link href="/guides/features/test-insights/flaky-tests/rust">不安定なテストの検出と隔離</.localized_link>を使用して、不安定なテストを調査し、ミュートまたはスキップします。<.localized_link href="/guides/features/test-sharding/rust">テストシャーディング</.localized_link>は、CI ワーカー全体に Cargo ターゲットを分散します。<.localized_link href="/guides/features/test-code-coverage/rust">コードカバレッジ</.localized_link>を有効にして、テスト実行の行カバレッジを追跡します。カバレッジベースのテスト選択とビルドワンス配布は、通常の Cargo テスト実行では利用できません。

## トラブルシューティング {#troubleshooting}

テスト実行がダッシュボードに表示されない場合は、デバッグ出力を有効にして、レポートが送信されなかった理由を確認します。

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
