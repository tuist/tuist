---
{
  "title": "Rust テストシャーディング",
  "titleTemplate": ":title · テストシャーディング · 機能 · ガイド · Tuist",
  "description": "過去のテスト実行時間に基づいて、CI ワーカー間で Cargo のテストターゲットを分散します。"
}
---
# Rust テストのシャーディング {#rust-test-sharding}

Tuist は、過去のターゲット実行時間に基づいて Cargo のテストターゲットを CI ワーカーに分散します。ユニットテストターゲット、統合テストターゲット、および各ライブラリの doctest は個別のモジュールとして扱われます。同一ターゲット内のテストはまとめて実行されます。

> [!IMPORTANT]
> **要件**
>
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> を構成し、プランニングジョブとワーカーで CLI の認証を行ってください。
> - ワークスペース内で `-p <package>` を使用して 1 つのパッケージを選択してください。複数パッケージのシャーディングはサポートされていません。
> - すべてのジョブで同じリビジョン、Rust ツールチェーン、パッケージ選択、フィーチャー、およびテストフィルターを使用してください。

## プランの作成 {#create-a-plan}

テストを実行せずにターゲットのコンパイルと列挙を行うため、`--no-run` にシャード数を追加します:

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

このコマンドは、`shard_plan_id` とゼロベースの `shards` 配列を含む JSON を出力します。GitHub Actions では、`shard-plan-id` と `shards` も `GITHUB_OUTPUT` に書き込まれます。明示的な参照が指定されていない場合、Tuist はサポートされている CI 環境から参照を導出します。

| オプション | 説明 |
| --- | --- |
| `--shard-max N` | 最大シャード数 |
| `--shard-min N` | 最小シャード数 |
| `--shard-total N` | 利用可能なターゲット数までの正確な数 |
| `--shard-max-duration N` | ターゲットとする最大シャード実行時間（ミリ秒） |

`--shard-total` を単独で使用するか、`--shard-min` と `--shard-max` を組み合わせて使用してください。過去の実行時間がない場合、プランナーはデフォルトのターゲット見積もりを使用します。シャードオプションなしの通常の `--no-run` は、ビルドのみを行うコマンドとして動作します。

## 各シャードの実行 {#execute-each-shard}

各ワーカーでプラン ID とシャードインデックスを設定し、同じ Cargo テスト引数を使用します:

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

あるいは、プラン ID を渡す代わりに `TUIST_SHARD_REFERENCE` をプランニングジョブの参照に設定します。Tuist は割り当てを取得し、Cargo にそれらのターゲットのみを実行するよう指示します。無効または互換性のない割り当ての場合、すべてのテストを実行するのではなくコマンドは失敗します。空の割り当ての場合、テストは実行されません。ワーカーからの結果は Test Insights でプランにリンクされ、<.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantining">検疫</.localized_link> は各シャード内で適用されます。

## 制限事項 {#limits}

これはターゲットレベルのシャーディングであり、一度ビルドして配布する方式ではありません。各ワーカーはソースのチェックアウトが必要で、独自のターゲットをビルドします。<.localized_link href="/guides/features/cache/rust">Cargo コンパレーションキャッシュ</.localized_link> を使用すれば、対象となるコンパイル成果物を再利用できます。Tuist はテスト実行ファイルをアップロードせず、他の Rust テストランナーも必要としません。

シャーディングには選択された 1 つのパッケージが必要です。複数パッケージのコマンドを絞り込むと Cargo の統合依存関係フィーチャーが変更される可能性があるため、Tuist は異なるフィーチャーグラフでテストを実行する代わりにそれを拒否します。複数パッケージのシャーディングがサポートされるまで、各パッケージを個別にプランニングしてください。

シャーディングには標準の libtest ハーネスとキャプチャされたデフォルト出力が必要です。quiet、verbose、alternate-format、uncaptured-output、およびカスタムハーネスのコマンドは拒否されます。Cargo がターゲットを一意に識別できない場合は、`-p <package>` で正確なワークスペースパッケージを選択してください。依存パッケージ、バージョン修飾セレクター、パッケージ/ターゲット名のグロブ、および Cargo のナイトリー `-C` オプションはシャーディングではサポートされていません。プランニングと実行の間でテスト選択を同一に保ってください。
