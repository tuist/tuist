---
{
  "title": "Rust ビルドインサイト",
  "titleTemplate": ":title · ビルドインサイト · 機能 · ガイド · Tuist",
  "description": "Tuist で遅いクレートを特定し、ビルドパフォーマンスを比較し、Rust コンパイラの警告やエラーを確認します。"
}
---
# Rust ビルドインサイト {#rust-build-insights}

Build Insights は、Cargo ビルドのボトルネックを特定し、チーム全体に影響する前に回帰を検出するのに役立ちます。ローカルビルドと CI を比較してビルド時間の変化を確認したり、各ビルドでコンパイルされたクレートを検査できます。

> [!IMPORTANT] Requirements
> - プロジェクトを接続して認証するには、<.localized_link href="/guides/get-started/rust-project">Rust プロジェクトのセットアップ</.localized_link>に従ってください。

## ビルドを報告する {#report-your-builds}

Tuist を介して通常の Cargo コマンドを実行します。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

mise を使用している場合は、通常の `cargo` コマンドを引き続き使用できるように <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo ラッパーを設定</.localized_link>してください。引数、ツールチェーンの選択、出力、および終了コードは変わりません。

## ビルドの遅延要因を見つける {#explore-your-builds}

ダッシュボードの **Builds → Build Runs** からビルドを開きます。日付、環境、Rust バージョンのフィルターを使用して類似のビルドを比較します。ビルドとそのキャッシュカウンターは、`tuist build cargo list`、`tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、および `list_cargo_builds` と `get_cargo_build` の <.localized_link href="/guides/features/agentic-coding/mcp">MCP ツール</.localized_link> からも利用できます。

**Overview** で、**Compiler jobs** を使用して遅いクレートを見つけます。**Duration** または **Started after**（Cargo コマンド開始からの経過時間）で並べ替えるか、クレート名またはルートソースファイルで検索します。

各行はクレートの `rustc` 呼び出しに対応し、複数のソースファイルを含む場合があります。**Crate root** はそのルートソースファイルを識別します。表示される時間はファイル単独ではなく、コンパイラジョブ全体のものです。異なるターゲットや設定に応じて、同じクレートが複数回表示されることがあります。コンパイラのメッセージは **Warnings** と **Errors** にグループ化されます。

## タイミングを読み解く {#timing-boundaries}

ビルド時間は、Cargo コマンド全体の実行にかかった時間です。コンパイラジョブは並列で実行されるため、それらの時間の合計はビルド時間と一致しません。

Cargo は再ビルドが必要なクレートのみをコンパイルします。すでに最新のクレートはコンパイラ一覧に表示されません。Tuist のコンパイルキャッシュを使用すると、復元されたジョブはコンパイラ実行としてではなく、キャッシュ測定値に表示されます。

Tuist はビルドスクリプトを個別に計測せず、ビルドタイムラインも表示しません。大規模なビルドでは最初の 500 件のコンパイラジョブが表示され、さらに記録がある場合はその旨の通知が表示されます。

## キャッシュ測定値を読み解く {#cache-measurements}

`tuist cargo` には、Tuist CLI に実装された実験的なコンパイルキャッシュが含まれています。セットアップ、Kura を介したリモート読み書き、サポートされるコンパイル、およびトラブルシューティングについては、<.localized_link href="/guides/features/cache/rust">Rust キャッシュガイド</.localized_link>に従ってください。

プロジェクトサイドバーの **Cargo Cache** を開き、ビルド全体のキャッシュヒット率、転送量、レイテンシ、スループットの測定値を追跡します。日付または環境でフィルターをかけ、日次トレンドと個別ビルドのヒット率を切り替えたり、最近のビルドを開いてキャッシュアクティビティを検査できます。キャッシュ測定値のないビルドはゼロとしてカウントされず、利用不可のままとなります。

ビルドの **Cache** タブを開き、タスクのヒット、ミス、ヒット率、ダウンロードおよびアップロードされたバイト数を確認します。このタブは、ビルドがキャッシュデータを報告する場合に表示されます。

- **Cacheable Tasks** は、キャッシュされた出力を再利用したコンパイラおよびビルドスクリプトのタスクを示します。タスクを検索またはフィルターし、キャッシュの読み書きレイテンシを検査し、行を展開して出力を確認できます。
- **CAS Outputs** はアーティファクトのダウンロードとアップロードを、サイズ、期間、スループットとともに示します。グラフは完了した転送をカウントします。すでに存在するアーティファクトと失敗した試行はテーブルに残ります。

**Hit** はキャッシュされた出力が再利用されたことを意味します。**Missed** はタスクが代わりにコンパイルされたことを意味します。ヒットはローカルとリモートに分割されません。CAS Outputs は記録されたアーティファクト操作を示します。

詳細な記録が欠落または不完全な場合、ページに通知が表示されます。サマリーはビルド全体を対象としています。回避された推定コンパイラ作業量は **節約された経過ビルド時間ではありません**。

> [!WARNING] Experimental compilation cache
> 最初のバージョンは、入力と出力が検証されたレジストリのリーフライブラリのみをキャッシュします。ワークスペースクレート、ビルドスクリプト、手続き型マクロ、他のクレートへの依存関係、増分コンパイル、ネイティブリンク、および実行可能ファイルは通常通りビルドされます。キャッシュキーは絶対パスを保持するため、異なるチェックアウトパス間での再利用はまだサポートされていません。

### テストを実行するビルド {#builds-that-run-tests}

`tuist cargo test` は、テストを含むコマンド全体の時間を報告します。また、<.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> を介して、doctest を含む個々のテスト結果も報告します。個々のテスト結果は **Tests** に表示され、コマンドの時間はビルドインサイトに表示されます。

## その他のコンパイラツール {#other-compiler-tools}

Tuist は、`RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER`、または Cargo 構成を通じて設定された既存のコンパイララッパーを維持し、`RUSTC_WORKSPACE_WRAPPER` をそのまま残します。事前に存在するグローバルラッパーがあると、Tuist のキャッシュとコンパイラオブザーバーが無効になります。Tuist は、そのラッパーが実際に rustc を実行したかどうかを確認できません。カスタムワークスペースラッパーも同様に、レポートに含まれるコンパイラジョブが少なくなる可能性があります。

Tuist は rustup を介して Cargo を検出します。カスタムインストールを使用している場合は、`TUIST_CARGO_EXECUTABLE` をその実行可能ファイルのパスに設定してください。直接ツールチェーンパスで Cargo を呼び出すと、mise のラッパーがバイパスされます。Cargo エイリアスは、`build` などの組み込みコマンドを置き換えることはできません。

Cargo のナイトリー `-C` オプションを使用する場合は、代わりにまずワークスペースに移動してください。Tuist は `-C` コマンドを転送しますが、そのビルドタイミングは収集しません。

## トラブルシューティング {#troubleshooting}

ビルドがダッシュボードに表示されない場合は、デバッグ出力を有効にして、レポートが送信されなかった理由を確認します。

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

レポート機能はビルドの結果を変更しません。
