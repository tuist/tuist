### 建置選項 {#build-options}

| 旗標 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | 最大分片數量。與 `--shard-max-duration` 一齊用嚟限制分片總數 |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | 最小分片數量 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | 指定分片數量（同 `--shard-min`/`--shard-max` 互斥）。使用套件粒度時，最後一個分片會包含剩餘項目 |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | 每個分片的目標最長持續時間（毫秒） |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`（預設）將整個測試模組分配到唔同分片；`suite` 則分配個別測試類別，以達致更細緻嘅負載平衡 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片計劃嘅唯一識別碼（喺支援嘅 CI 提供者上自動衍生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist 寫入優化後分片歸檔嘅路徑，而唔係將測試產物上傳到遠端儲存空間 |
