### ビルドオプション {#build-options}

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | シャードの最大数。`--shard-max-duration` と組み合わせてシャード数を制限します |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | シャードの最小数 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | シャードの正確な数（`--shard-min`/`--shard-max` と排他）。スイート粒度の場合、最後のシャードは残りすべてを含みます |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | シャードあたりの目標最大時間（ミリ秒） |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`（デフォルト）はテストモジュール全体をシャードに分散します。`suite` は個々のテストクラスを分散し、より細かくバランスを取ります |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | シャードプランの一意の識別子（対応する CI プロバイダーで自動導出） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist が最適化されたシャードアーカイブを書き込むパス。テスト成果物をリモートストレージにアップロードしません |
