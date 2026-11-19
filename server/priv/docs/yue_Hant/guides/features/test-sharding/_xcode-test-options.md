### 測試選項 {#test-options}

| 標誌 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 要執行的分片索引（從零開始） |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | 建置階段產生的精確分片計劃識別碼。自動產生的提供者輸出會自動包含此值 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片計劃的唯一識別碼（在支援的 CI 提供者上自動衍生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | 本機管理之分片封存的路徑；Tuist 會將其解壓縮，而非從遠端儲存空間下載測試產品 |

Tuist 會下載 `.xctestproducts` 套件，並篩選出僅包含指派給該分片的測試。
