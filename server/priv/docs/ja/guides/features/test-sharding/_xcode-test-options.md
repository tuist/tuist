### テストオプション {#test-options}

| フラグ | 環境変数 | 説明 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 実行するシャードのゼロベースのインデックス |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | ビルドフェーズによって出力される正確なシャードプラン識別子。生成されたプロバイダーの出力にはこの値が自動的に含まれます |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | シャードプランの一意の識別子（サポートされているCIプロバイダーで自動導出） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | ローカルで管理されるシャードアーカイブへのパス。Tuistはリモートストレージからテスト製品をダウンロードする代わりにこれを展開します |

Tuistは`.xctestproducts`バンドルをダウンロードし、そのシャードに割り当てられたテストのみを含むようにフィルタリングします。
