---
{
  "title": "Rust テストインサイト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist ダッシュボードで、Rust の doctest を含む Cargo テストの結果を追跡します。"
}
---
# Rust テストのインサイト {#rust-test-insights}

Tuist は `cargo test` からの個別のテスト結果（ユニットテスト、統合テスト、ドキュメントテストを含む）をレポートします。Rust の依存関係や追加のテストランナーは不要です。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust プロジェクトのセットアップ</.localized_link>に従ってください。

## テスト実行をレポートする {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

mise Cargo ラッパーを設定しておけば、引き続き `cargo test` と入力できます。Cargo は通常の引数、出力、終了コードでテストをコンパイルおよび実行します。レポートの失敗がテストの結果に影響を与えることはありません。

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

フィルタリングされたテストや失敗後に実行されなかったテストは、合格としてレポートされることはありません。結果はダッシュボードの **テスト** に表示されます。

## 継続的インテグレーション {#continuous-integration}

Tuist は GitHub Actions、GitLab CI、Bitrise、CircleCI、Buildkite、Codemagic を認識し、各実行をその CI ジョブにリンクします。他の CI システムでは、`CI` 環境変数が設定されている場合、その実行は CI 実行としてカウントされます。ほとんどの CI システムはこの変数を設定しますが、Fly.io Machines など設定しない環境では手動で設定してください。不安定なテストの検出は CI 実行間でのみ比較されます。

ブランチではなくコミットをチェックアウトするジョブでは、Git に名前付けるべきブランチがないため、その実行にはブランチ情報が含まれません。Tuist が認識する CI システムでは、ブランチ情報はプロバイダーから取得されます。それ以外の環境では、`TUIST_GIT_BRANCH` で指定してください。

```sh
CI=true TUIST_GIT_BRANCH=main tuist cargo test --workspace
```

## パッケージ、モジュール、およびテストケース {#test-hierarchy}

Tuist は Cargo パッケージとターゲットごとに結果をグループ化します。Rust モジュールパスは、ターゲット内の個別のテストをグループ化します。

| ダッシュボードのラベル | Rust での意味 | 例 |
| --- | --- | --- |
| モジュール | Cargo パッケージとターゲット | `store::api` |
| テストスイート | Rust モジュールパス | `api::authentication` |
| テストケース | 個別のテスト | `rejects_invalid_token` |

ドキュメントテストは `store::doctest/store` のような別個のモジュールを使用します。名前にソースの位置が含まれるため、例を移動するとその識別子が変更される可能性があります。

## ドキュメントテストと所要時間 {#cargo-test}

ドキュメントテストは、`compile_fail`、`should_panic`、`no_run` の例を含め、通常のテストコマンドで実行されます。ドキュメントテストのみを実行するには：

```sh
tuist cargo test --doc
```

安定版の libtest はスイート全体の時間をレポートしますが、個別のテストの所要時間はレポートしません。利用できないタイミング情報は、ケースごとの所要時間の履歴や分析から除外されますが、テストの結果は信頼性と実行回数に引き続き反映されます。

## レポートの制限 {#reporting-limits}

個別の結果は Cargo/libtest のデフォルト出力から収集されます。`--no-run`、`--list`、quiet または Cargo-verbose 出力、代替フォーマット、またはキャプチャされていないテスト出力を使用するコマンドは、個別のテストレポートなしで通常どおり実行されます。カスタムハーネス、不完全なサマリー、曖昧なターゲット属性、 oversized なレポートはアップロードされません。

ワークスペースのパッケージに同名の統合ターゲットがある場合は、`-p <package>` で一つを選択してください。レポート機能は正確なワークスペースパッケージ名をサポートします。依存パッケージ、バージョン修飾セレクター、およびグロブパターンは通常どおり実行されますが、レポートされません。絶対パスのドキュメントテストパスは、チェックアウトパスがテストの識別子に含まれないように省略されます。

Tuist は結果を収集しながら出力をストリーミングします。これにより、自動的な色検出に影響を与える可能性があります。Cargo 終了後も出力パイプを開いたままにするバックグラウンドプロセスがあると、レポートが省略される原因になりますが、Cargo の終了ステータスは変更されません。

## 信頼性と選択 {#reliability-and-selection}

<.localized_link href="/guides/features/test-insights/flaky-tests/rust">不安定なテストの検出と隔離</.localized_link>を使用して、不安定なテストを調査し、ミュートまたはスキップします。<.localized_link href="/guides/features/test-sharding/rust">テストシャーディング</.localized_link>は、Cargo ターゲット全体を CI ワーカー間に分散します。<.localized_link href="/guides/features/test-code-coverage/rust">コードカバレッジ</.localized_link>を有効にして、テスト実行の行カバレッジを追跡します。カバレッジベースのテスト選択とビルドワンス配信は、通常の Cargo テスト実行では利用できません。

## トラブルシューティング {#troubleshooting}

テスト実行がダッシュボードに表示されない場合は、デバッグ出力を有効にして、レポートが送信されなかった理由を確認してください。

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
