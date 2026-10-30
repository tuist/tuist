---
{
  "title": "Rust Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Cargo test results, including Rust doctests, in the Tuist dashboard."
}
---
# Rust テストインサイト {#rust-test-insights}

Tuist は、`cargo test` からの個別のテスト結果（ユニットテスト、統合テスト、ドキュメントテストを含む）を報告します。Rust の依存関係や追加のテストランナーは不要です。

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/get-started/rust-project">Rust プロジェクトのセットアップ</.localized_link>に従ってください。

## テスト実行を報告する {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

mise Cargo wrapper が設定されていれば、引き続き `cargo test` と入力できます。Cargo は通常どおり引数、出力、終了コードを使用してテストをコンパイルおよび実行します。報告の失敗がテストの結果を変更することはありません。

通常どおりパッケージを選択したり、テストをフィルタリングできます：

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist が追跡する項目 {#what-is-tracked}

- 完了したテストスイートからの合格、不合格、および無視されたテスト。
- ユニットテスト、統合テスト、およびドキュメントテスト。
- スイート全体の所要時間。
- 利用可能なブランチ、コミット、CI、およびランナーのメタデータ。

フィルタリングされたテストや失敗後に実行されなかったテストは、合格として報告されることはありません。結果はダッシュボードの **Tests** に表示されます。

## パッケージ、モジュール、およびテストケース {#test-hierarchy}

Tuist は Cargo パッケージとターゲットごとに結果をグループ化します。Rust モジュールパスは、ターゲット内の個別のテストをグループ化します：

| ダッシュボードラベル | Rust の意味 | 例 |
| --- | --- | --- |
| モジュール | Cargo パッケージとターゲット | `store::api` |
| テストスイート | Rust モジュールパス | `api::authentication` |
| テストケース | 個別のテスト | `rejects_invalid_token` |

ドキュメントテストは `store::doctest/store` のような別のモジュールを使用します。名前にはソースの場所が含まれるため、例を移動するとその識別子が変更される可能性があります。

## ドキュメントテストと所要時間 {#cargo-test}

ドキュメントテストは、`compile_fail`、`should_panic`、および `no_run` の例を含め、通常のテストコマンドで実行されます。ドキュメントテストのみを実行するには：

```sh
tuist cargo test --doc
```

安定版の libtest はスイート全体の時間を報告しますが、個別のテストの所要時間は報告しません。利用できないタイミング情報は、ケースごとの所要時間の履歴や所要時間の分析から除外されますが、テストの結果は信頼性と実行回数に依然として寄与します。

## 報告の制限 {#reporting-limits}

個別の結果は Cargo/libtest のデフォルト出力から収集されます。`--no-run`、`--list`、quiet または Cargo-verbose 出力、代替フォーマット、またはキャプチャされていないテスト出力を使用するコマンドは、個別のテスト報告なしで通常どおり実行されます。カスタムハーネス、不完全なサマリー、曖昧なターゲット属性、および大きすぎるレポートはアップロードされません。

ワークスペースパッケージに同名の統合ターゲットがある場合は、`-p <package>` で 1 つを選択してください。報告は正確なワークスペースパッケージ名をサポートします。依存パッケージ、バージョン修飾セレクター、およびグロブは通常どおり実行されますが、報告されません。絶対ドキュメントテストパスは、チェックアウトパスがテスト識別子に含まれないように省略されます。

Tuist は結果を収集しながら出力をストリーミングします。これにより、自動色検出に影響を与える可能性があります。Cargo 終了後も出力パイプを開いたままにするバックグラウンドプロセスがあると、レポートが省略される原因になりますが、Cargo の終了ステータスは変更されません。

## 信頼性と選択 {#reliability-and-selection}

<.localized_link href="/guides/features/test-insights/flaky-tests/rust">不安定なテストの検出と隔離</.localized_link> を使用して、不安定なテストを調査し、ミュートまたはスキップします。<.localized_link href="/guides/features/test-sharding/rust">テストシャーディング</.localized_link> は、CI ワーカー全体に Cargo ターゲットを分散します。カバレッジの取り込み、カバレッジベースのテスト選択、およびビルドワンス配信は、通常の Cargo テスト実行では利用できません。

## トラブルシューティング {#troubleshooting}

テスト実行がダッシュボードに表示されない場合は、デバッグ出力を有効にして、レポートが送信されなかった理由を確認してください：

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
