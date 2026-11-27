### 建構選項 {#build-options}

| 旗標 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | 最大分片數量。與 `--shard-max-duration` 搭配使用以限制分片數量 |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | 最小分片數量 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | 精確分片數量（與 `--shard-min`/`--shard-max` 互斥）。使用套件粒度時，最後一個分片會作為收容所有剩餘項目的分片 |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | 每個分片的目標最長持續時間（毫秒） |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`（預設）將整個測試模組分配到各分片；`suite` 則分配個別測試類別，以實現更細緻的負載平衡 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片計劃的唯一識別碼（在支援的 CI 提供者上自動衍生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist 寫入最佳化分片封存檔的路徑，而非將測試產物上傳至遠端儲存空間 |
