---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Cargo test targets across CI workers using historical test durations."
}
---
# Rust テストシャーディング {#rust-test-sharding}

Tuist は、過去のターゲット実行時間を使用して、CI ワーカー間で Cargo のテストターゲットを分散します。ユニットテストターゲット、統合テストターゲット、および各ライブラリの doctests は個別のモジュールです。1 つのターゲット内のテストはまとめて実行されます。

> [!IMPORTANT] Requirements
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> を設定し、プランニングジョブとワーカーで CLI を認証してください。
> - ワークスペース内で `-p <package>` を使用して 1 つのパッケージを選択してください。複数パッケージのシャーディングはサポートされていません。
> - すべてのジョブで同じリビジョン、Rust ツールチェーン、パッケージ選択、フィーチャー、およびテストフィルターを使用してください。

## プランを作成する {#create-a-plan}

テストを実行せずにターゲットをコンパイルして列挙するために、`--no-run` にシャード数を追加します:

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

コマンドは、`shard_plan_id` と 0 から始まる `shards` 配列を含む JSON を出力します。GitHub Actions では、`shard-plan-id` と `shards` も `GITHUB_OUTPUT` に書き込まれます。明示的な参照がない場合、Tuist はサポートされている CI 環境から参照を導出します。

| オプション | 説明 |
| --- | --- |
| `--shard-max N` | 最大シャード数 |
| `--shard-min N` | 最小シャード数 |
| `--shard-total N` | 利用可能なターゲットまでの正確な数 |
| `--shard-max-duration N` | ターゲットの最大シャード期間（ミリ秒単位） |

`--shard-total` だけを単独で使用するか、`--shard-min` と `--shard-max` を組み合わせて使用します。過去の期間データがない場合、プランナーはデフォルトのターゲット見積もりを使用します。シャードオプションなしの通常の `--no-run` は、ビルドのみを行うコマンドとして残ります。

## 各シャードを実行する {#execute-each-shard}

各ワーカーでプラン ID とシャードインデックスを設定し、同じ Cargo テスト引数を使用します:

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

あるいは、プラン ID を渡す代わりに、`TUIST_SHARD_REFERENCE` をプランニングジョブの参照に設定します。Tuist は割り当てを取得し、Cargo にそれらのターゲットのみを実行するように指示します。無効または互換性のない割り当ての場合、すべてのテストを実行するのではなく、コマンドは失敗します。空の割り当ての場合、テストは実行されません。ワーカーからの結果は Test Insights でプランにリンクされ、<.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantine">quarantine</.localized_link> が各シャード内で適用されます。

## 制限事項 {#limits}

これはターゲットレベルのシャーディングであり、一度ビルドして配布するものではありません。各ワーカーにはソースのチェックアウトが必要で、独自のターゲットをビルドします。<.localized_link href="/guides/features/cache/rust">Cargo コンパイルキャッシュ</.localized_link> は、該当するコンパイル出力を再利用できます。Tuist はテスト実行ファイルをアップロードせず、別の Rust テストランナーも必要としません。

シャーディングには、選択された 1 つのパッケージが必要です。複数パッケージのコマンドを絞り込むと、Cargo の統一された依存関係フィーチャーが変更される可能性があるため、Tuist は異なるフィーチャーグラフでテストを実行する代わりにそれを拒否します。複数パッケージのシャーディングがサポートされるまで、各パッケージを個別にプランニングしてください。

シャーディングには標準の libtest ハーネスとキャプチャされたデフォルト出力が必要です。Quiet、verbose、alternate-format、uncaptured-output、および custom-harness コマンドは拒否されます。Cargo がターゲットを一意に識別できない場合は、`-p <package>` で正確なワークスペースパッケージを選択してください。依存パッケージ、バージョン限定セレクター、パッケージ/ターゲット名のグロブ、および Cargo のナイトリー `-C` オプションは、シャーディングではサポートされていません。プランニングと実行の間でテスト選択を同一に保ってください。
