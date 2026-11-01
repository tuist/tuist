---
{
  "title": "Rust テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで、Rust の doctests を含む Cargo のテスト結果を追跡します。"
}
---
# Rust テストのインサイト {#rust-test-insights}

Tuist は `cargo test` から単体テスト、結合テスト、ドックテストを含む個々のテスト結果をレポートします。Rust の依存関係や追加のテストランナーは不要です。

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/get-started/rust-project">Rust プロジェクトのセットアップ</.localized_link>に従ってください。

## テスト実行をレポートする {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

mise Cargo ラッパーを設定すれば、`cargo test` をそのまま入力し続けられます。Cargo は通常どおり引数、出力、終了コードを用いてテストをコンパイル・実行します。レポートの失敗がテストの結果を変えることはありません。

パッケージを選択したり、テストをフィルタリングしたりできます。

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist が追跡する項目 {#what-is-tracked}

- 完了したテストスイートからの合格、不合格、無視されたテスト。
- 単体テスト、結合テスト、ドックテスト。
- スイート全体の所要時間。
- 利用可能なブランチ、コミット、CI、およびランナーのメタデータ。

フィルタリングされたテストや失敗後に実行されなかったテストは合格としてレポートされません。結果はダッシュボードの **テスト** に表示されます。

## パッケージ、モジュール、テストケース {#test-hierarchy}

Tuist は Cargo パッケージとターゲットごとに結果をグループ化します。Rust のモジュールパスは、ターゲット内の個々のテストをグループ化します。

| ダッシュボードのラベル | Rust での意味 | 例 |
| --- | --- | --- |
| モジュール | Cargo パッケージとターゲット | `store::api` |
| テストスイート | Rust モジュールパス | `api::authentication` |
| テストケース | 個々のテスト | `rejects_invalid_token` |

ドックテストは `store::doctest/store` のような別個のモジュールを使用します。名前にソースの場所が含まれるため、例を移動するとその識別子が変更される可能性があります。

## ドックテストと所要時間 {#cargo-test}

ドックテストは通常のテストコマンドで実行され、`compile_fail`、`should_panic`、`no_run` の例を含みます。ドックテストのみを実行するには:

```sh
tuist cargo test --doc
```

安定版の libtest はスイート全体の時間をレポートしますが、個々のテストの所要時間はレポートしません。利用できないタイミング情報はケースごとの所要時間の履歴や所要時間の分析から除外されますが、テストの結果は信頼性と実行回数に引き続き反映されます。

## レポートの制限 {#reporting-limits}

個々の結果は Cargo/libtest のデフォルト出力から収集されます。`--no-run`、`--list`、quiet または Cargo-verbose 出力、代替フォーマット、キャプチャされていないテスト出力を使用するコマンドは、個々のテストのレポートなしで通常どおり実行されます。カスタムハーネス、不完全なサマリー、曖昧なターゲットの帰属、 oversized なレポートはアップロードされません。

ワークスペースのパッケージに同名の結合ターゲットがある場合は、`-p <package>` で一つを選択してください。レポートは正確なワークスペースパッケージ名をサポートします。依存パッケージ、バージョン修飾セレクター、グロブは通常どおり実行されますが、レポートされません。絶対パスのドックテストパスは、チェックアウトパスがテストの識別子に含まれないように省略されます。

Tuist は結果を収集しながら出力をストリーミングします。これにより自動色検出に影響が出る可能性があります。Cargo 終了後も出力パイプを開き続けるバックグラウンドプロセスがあると、レポートが省略される可能性がありますが、Cargo の終了ステータスは変わりません。

## 信頼性と選択 {#reliability-and-selection}

<.localized_link href="/guides/features/test-insights/flaky-tests/rust">flaky テストの検出と隔離</.localized_link>を使用して不安定なテストを調査し、ミュートまたはスキップできます。<.localized_link href="/guides/features/test-sharding/rust">テストシャーディング</.localized_link>は Cargo ターゲット全体を CI ワーカーに分散します。カバレッジの取り込み、カバレッジベースのテスト選択、ビルドワンスの配布は、通常の Cargo テスト実行では利用できません。

## トラブルシューティング {#troubleshooting}

テスト実行がダッシュボードに表示されない場合は、デバッグ出力を有効にしてレポートが送信されなかった理由を確認してください。

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
