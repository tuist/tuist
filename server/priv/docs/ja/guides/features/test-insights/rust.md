---
{
  "title": "Rust テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで、Rust のドックテストを含む Cargo テストの結果を追跡します。"
}
---
# Rust テストのインサイト {#rust-test-insights}

Tuist は `cargo test` からの個々のテスト結果を報告します。ユニットテスト、統合テスト、ドックテストが含まれます。Rust の依存関係や追加のテストランナーは不要です。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust プロジェクトのセットアップ</.localized_link>に従ってください。

## テスト実行を報告する {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

mise の Cargo ラッパーを設定しておけば、引き続き `cargo test` を入力できます。Cargo は通常の引数、出力、終了コードでテストをコンパイルして実行します。レポートの失敗がテストの結果に影響することはありません。

通常どおりパッケージを選択したり、テストをフィルタリングできます。

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist が追跡する情報 {#what-is-tracked}

- 完了したテストスイートから得られる、合格・不合格・無視されたテスト。
- ユニットテスト、統合テスト、ドックテスト。
- スイート全体の所要時間。
- 利用可能なブランチ、コミット、CI、およびランナーのメタデータ。

フィルタリングされたテストや、失敗後に実行されなかったテストは合格として報告されません。結果はダッシュボードの **Tests** に表示されます。

## パッケージ、モジュール、テストケース {#test-hierarchy}

Tuist は結果を Cargo パッケージとターゲットごとにグループ化します。Rust のモジュールパスは、ターゲット内の個々のテストをグループ化します。

| ダッシュボードのラベル | Rust での意味 | 例 |
| --- | --- | --- |
| モジュール | Cargo パッケージとターゲット | `store::api` |
| テストスイート | Rust モジュールパス | `api::authentication` |
| テストケース | 個々のテスト | `rejects_invalid_token` |

ドックテストは `store::doctest/store` のような別個のモジュールを使用します。名前にはソースの場所が含まれるため、例を移動すると識別子が変わることがあります。

## ドックテストと所要時間 {#cargo-test}

ドックテストは普段のテストコマンドで実行され、`compile_fail`、`should_panic`、`no_run` の例も含まれます。ドックテストのみを実行するには:

```sh
tuist cargo test --doc
```

安定版の libtest はスイート全体の時間を報告しますが、個々のテストの所要時間は報告しません。利用できないタイミング情報は、ケースごとの所要時間の履歴や所要時間の分析から除外されますが、テストの結果は信頼性と実行回数に反映されます。

## レポートの制限 {#reporting-limits}

個々の結果は Cargo/libtest のデフォルト出力から収集されます。`--no-run`、`--list`、quiet または Cargo-verbose 出力、代替フォーマット、キャプチャされていないテスト出力を使用するコマンドは、個々のテストのレポートなしで通常どおり実行されます。カスタムハーネス、不完全なサマリー、あいまいなターゲットの帰属、 oversized なレポートはアップロードされません。

ワークスペースのパッケージに同名の統合ターゲットがある場合は、`-p <package>` で 1 つを選択してください。レポートは正確なワークスペースパッケージ名をサポートします。依存パッケージ、バージョン修飾セレクター、グロブは通常どおり実行されますが、レポートされません。絶対パスのドックテストパスは省略され、チェックアウトパスがテストの識別子に含まれないようにします。

Tuist は結果を収集しながら出力をストリーミングします。これにより自動色検出に影響が出る可能性があります。Cargo 終了後も出力パイプを開いたままにするバックグラウンドプロセスがあると、レポートが省略される可能性がありますが、Cargo の終了ステータスは変わりません。

## 信頼性と選択 {#reliability-and-selection}

<.localized_link href="/guides/features/test-insights/flaky-tests/rust">flaky test detection and quarantine</.localized_link> を使用して不安定なテストを調査し、ミュートまたはスキップします。<.localized_link href="/guides/features/test-sharding/rust">Test sharding</.localized_link> は Cargo ターゲット全体を CI ワーカーに分散します。<.localized_link href="/guides/features/test-code-coverage/rust">code coverage</.localized_link> を有効にして、テスト実行の行カバレッジを追跡します。カバレッジベースのテスト選択と build-once 配布は、通常の Cargo テスト実行では利用できません。

## トラブルシューティング {#troubleshooting}

テスト実行がダッシュボードに表示されない場合は、デバッグ出力を有効にしてレポートが送信されなかった理由を確認します。

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
