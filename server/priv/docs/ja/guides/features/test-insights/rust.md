---
{
  "title": "Rust テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで、Rust の doctest を含む Cargo テストの結果を追跡します。"
}
---
# Rustテストのインサイト {#rust-test-insights}

Tuistは`cargo test`からの個々のテスト結果（ユニットテスト、統合テスト、doctestを含む）を報告します。Rustの依存関係や追加のテストランナーは不要です。

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/get-started/rust-project">Rustプロジェクトのセットアップ</.localized_link>に従ってください。

## テスト実行を報告する {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

miseのCargoラッパーが構成されていれば、引き続き`cargo test`と入力できます。Cargoは通常どおり引数、出力、終了コードを使用してテストをコンパイル・実行します。レポートの失敗がテストの結果に影響することはありません。

通常どおりパッケージを選択したり、テストをフィルタリングできます。

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuistが追跡する項目 {#what-is-tracked}

- 完了したテストスイートからの合格・不合格・無視されたテスト。
- ユニットテスト、統合テスト、およびdoctest。
- スイート全体の所要時間。
- 利用可能なブランチ、コミット、CI、およびランナーのメタデータ。

フィルタリングされたテストや失敗後に実行されなかったテストは、合格として報告されることはありません。結果はダッシュボードの**テスト**に表示されます。

## パッケージ、モジュール、およびテストケース {#test-hierarchy}

TuistはCargoのパッケージとターゲットごとに結果をグループ化します。Rustのモジュールパスは、ターゲット内の個々のテストをグループ化します。

| ダッシュボードのラベル | Rustでの意味 | 例 |
| --- | --- | --- |
| モジュール | Cargoのパッケージとターゲット | `store::api` |
| テストスイート | Rustのモジュールパス | `api::authentication` |
| テストケース | 個々のテスト | `rejects_invalid_token` |

Doctestは`store::doctest/store`などの別個のモジュールを使用します。名前にはソースの場所が含まれるため、例を移動するとその識別子が変更される可能性があります。

## Doctestと所要時間 {#cargo-test}

Doctestは通常のテストコマンドで実行され、`compile_fail`、`should_panic`、および`no_run`の例を含みます。Doctestのみを実行するには：

```sh
tuist cargo test --doc
```

安定版のlibtestはスイート全体の時間を報告しますが、個々のテストの所要時間は報告しません。利用できないタイミング情報はケースごとの所要時間の履歴や分析から除外されますが、テストの結果は信頼性と実行回数に依然として反映されます。

## レポートの制限 {#reporting-limits}

個々の結果はCargo/libtestのデフォルト出力から収集されます。`--no-run`、`--list`、quietまたはCargoの詳細出力、代替フォーマット、キャプチャされていないテスト出力を使用するコマンドは、個々のテストレポートなしで通常どおり実行されます。カスタムハーネス、不完全なサマリー、曖昧なターゲットの帰属、 oversizedなレポートはアップロードされません。

ワークスペースのパッケージに同名の統合ターゲットがある場合は、`-p <package>`で1つを選択してください。レポートは正確なワークスペースパッケージ名をサポートします。依存パッケージ、バージョン限定セレクター、グロブは通常どおり実行されますが、レポートされません。絶対パスのdoctestパスは省略され、チェックアウトパスがテストの識別子に含まれないようにします。

Tuistは結果を収集しながら出力をストリーミングします。これにより自動カラー検出に影響を与える可能性があります。Cargo終了後も出力パイプを開いたままにするバックグラウンドプロセスがあると、レポートが省略される可能性がありますが、Cargoの終了ステータスは変更されません。

## 信頼性と選択 {#reliability-and-selection}

<.localized_link href="/guides/features/test-insights/flaky-tests/rust">flakyテストの検出と隔離</.localized_link>を使用して不安定なテストを調査し、ミュートまたはスキップします。<.localized_link href="/guides/features/test-sharding/rust">テストシャーディング</.localized_link>はCIワーカー全体にCargoターゲットを分散します。カバレッジの取り込み、カバレッジベースのテスト選択、およびビルドワンスの配布は、通常のCargoテスト実行では利用できません。

## トラブルシューティング {#troubleshooting}

テスト実行がダッシュボードに表示されない場合は、デバッグ出力を有効にしてレポートが送信されなかった理由を確認します。

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
