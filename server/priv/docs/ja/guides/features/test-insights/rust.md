---
{
  "title": "Rust テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで、Rust の doctest を含む Cargo テストの結果を追跡します。"
}
---
# Rustテストのインサイト {#rust-test-insights}

Tuistは`cargo test`からの個々のテスト結果（ユニットテスト、統合テスト、ドキュメントテストを含む）を報告します。Rustの依存関係や追加のテストランナーは不要です。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/rust-project">Rustプロジェクトのセットアップ</.localized_link>に従ってください。

## テスト実行を報告する {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

miseのCargoラッパーを設定すると、引き続き`cargo test`と入力できます。Cargoは通常どおり引数、出力、終了コードを使用してテストをコンパイルおよび実行します。レポートの失敗がテストの結果を変えることはありません。

通常どおりパッケージを選択したり、テストをフィルタリングできます。

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuistが追跡する項目 {#what-is-tracked}

- 完了したテストスイートからの合格、不合格、無視されたテスト。
- ユニットテスト、統合テスト、ドキュメントテスト。
- スイート全体の所要時間。
- 利用可能なブランチ、コミット、CI、およびランナーのメタデータ。

フィルタリングされたテストや失敗後に実行されなかったテストは、合格として報告されることはありません。結果はダッシュボードの**テスト**に表示されます。

## パッケージ、モジュール、テストケース {#test-hierarchy}

TuistはCargoのパッケージとターゲットごとに結果をグループ化します。Rustのモジュールパスは、ターゲット内の個々のテストをグループ化します。

| ダッシュボードのラベル | Rustでの意味 | 例 |
| --- | --- | --- |
| モジュール | Cargoのパッケージとターゲット | `store::api` |
| テストスイート | Rustのモジュールパス | `api::authentication` |
| テストケース | 個々のテスト | `rejects_invalid_token` |

ドキュメントテストは`store::doctest/store`などの別個のモジュールを使用します。名前にはソースの位置が含まれるため、例を移動するとその識別子が変更される可能性があります。

## ドキュメントテストと所要時間 {#cargo-test}

ドキュメントテストは通常のテストコマンドで実行され、`compile_fail`、`should_panic`、`no_run`の例を含みます。ドキュメントテストのみを実行するには：

```sh
tuist cargo test --doc
```

安定版のlibtestはスイート全体の時間を報告しますが、個々のテストの所要時間は報告しません。利用できないタイミング情報はケースごとの所要時間の履歴や分析から除外されますが、テストの結果は信頼性と実行回数に依然として寄与します。

## 報告の制限 {#reporting-limits}

個々の結果はCargo/libtestのデフォルト出力から収集されます。`--no-run`、`--list`、quietまたはCargo-verboseな出力、代替フォーマット、キャプチャされていないテスト出力を使用するコマンドは、個々のテストの報告なしで通常どおり実行されます。カスタムハーネス、不完全なサマリー、曖昧なターゲットの帰属、大きすぎるレポートはアップロードされません。

ワークスペースのパッケージに同名の統合ターゲットがある場合は、`-p <package>`で1つを選択してください。報告は正確なワークスペースパッケージ名をサポートします。依存パッケージ、バージョン修飾セレクター、グロブパターンは通常どおり実行されますが、報告されません。絶対パスのドキュメントテストパスは、チェックアウトパスがテストの識別子に含まれないように省略されます。

Tuistは結果を収集しながら出力をストリーミングします。これにより自動色検出に影響が出る可能性があります。Cargo終了後も出力パイプを開いたままにするバックグラウンドプロセスがあると、レポートが省略される原因になりますが、Cargoの終了ステータスは変わりません。

## 信頼性と選択 {#reliability-and-selection}

<.localized_link href="/guides/features/test-insights/flaky-tests/rust">不安定なテストの検出と隔離</.localized_link>を使用して不安定なテストを調査し、ミュートまたはスキップします。<.localized_link href="/guides/features/test-sharding/rust">テストシャーディング</.localized_link>はCargoターゲット全体をCIワーカーに分散します。カバレッジの取り込み、カバレッジベースのテスト選択、ビルド一度きりの分散は、通常のCargoテスト実行では利用できません。

## トラブルシューティング {#troubleshooting}

テスト実行がダッシュボードに表示されない場合は、デバッグ出力を有効にしてレポートが送信されなかった理由を確認してください。

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
