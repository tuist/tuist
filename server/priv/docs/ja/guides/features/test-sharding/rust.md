---
{
  "title": "Rust テストのシャーディング",
  "titleTemplate": ":title · テストのシャーディング · 機能 · ガイド · Tuist",
  "description": "過去のテスト実行時間に基づいて、CI ワーカー間で Cargo のテストターゲットを分散します。"
}
---
# Rust テストのシャーディング {#rust-test-sharding}

Tuist は、過去のターゲット実行時間に基づいて Cargo のテストターゲットを CI ワーカーに分散します。ユニットテストターゲット、統合テストターゲット、および各ライブラリの doctest は個別のモジュールとして扱われます。同一ターゲット内のテストはまとめて実行されます。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> を設定し、プランニングジョブとワーカーで CLI の認証を行ってください。
> - ワークスペース内で `-p <package>` を使用して 1 つのパッケージを選択してください。複数パッケージのシャーディングはサポートされていません。
> - すべてのジョブで同じリビジョン、Rust ツールチェーン、パッケージ選択、機能、およびテストフィルターを使用してください。

## プランの作成 {#create-a-plan}

テストを実行せずにターゲットをコンパイルして列挙するため、`--no-run` にシャード数を追加します:

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

コマンドは、`shard_plan_id` とゼロベースの `shards` 配列を含む JSON を出力します。GitHub Actions では、`shard-plan-id` と `shards` も `GITHUB_OUTPUT` に書き込まれます。明示的な参照がない場合、Tuist はサポートされている CI 環境から参照を導出します。

| オプション | 説明 |
| --- | --- |
| `--shard-max N` | 最大シャード数 |
| `--shard-min N` | 最小シャード数 |
| `--shard-total N` | 利用可能なターゲット数までの正確な数 |
| `--shard-max-duration N` | ターゲットとする最大シャード実行時間（ミリ秒） |

`--shard-total` だけを指定するか、`--shard-min` と `--shard-max` を組み合わせて使用してください。過去の実行時間がない場合、プランナーはデフォルトのターゲット見積もりを使用します。シャードオプションなしの通常の `--no-run` は、ビルドのみを行うコマンドとして動作します。

## 各シャードの実行 {#execute-each-shard}

各ワーカーでプラン ID とシャードインデックスを設定し、同じ Cargo テスト引数を使用します:

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

あるいは、プラン ID を渡す代わりに `TUIST_SHARD_REFERENCE` をプランニングジョブの参照に設定します。Tuist は割り当てを取得し、Cargo にそれらのターゲットのみを実行するよう指示します。無効または互換性のない割り当ての場合、すべてのテストを実行するのではなくコマンドが失敗します。空の割り当ての場合、テストは実行されません。ワーカーからの結果は Test Insights でプランにリンクされ、<.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantining">検疫</.localized_link> が各シャード内で適用されます。

## 制限事項 {#limits}

これはターゲットレベルのシャーディングであり、一度ビルドして配布する方式ではありません。各ワーカーにはソースのチェックアウトが必要で、独自のターゲットをビルドします。<.localized_link href="/guides/features/cache/rust">Cargo コンパイルキャッシュ</.localized_link> を使用すれば、対象となるコンパイル成果物を再利用できます。Tuist はテスト実行バイナリをアップロードせず、他の Rust テストランナーも必要としません。

シャーディングでは 1 つのパッケージを選択する必要があります。複数パッケージのコマンドを絞り込むと Cargo の統一された依存関係の機能が変更される可能性があるため、Tuist は異なる機能グラフでテストを実行する代わりにそれを拒否します。複数パッケージのシャーディングがサポートされるまで、各パッケージを個別にプランニングしてください。

シャーディングには標準の libtest ハーネスとキャプチャされたデフォルト出力が必要です。quiet、verbose、alternate-format、uncaptured-output、およびカスタムハーネスのコマンドは拒否されます。Cargo がターゲットを一意に識別できない場合は、`-p <package>` を使用してワークスペース内の正確なパッケージを選択してください。依存パッケージ、バージョン限定セレクター、パッケージ/ターゲット名のグロブ、および Cargo の nightly `-C` オプションはシャーディングでサポートされていません。プランニングと実行の間でテスト選択を同一に保ってください。
