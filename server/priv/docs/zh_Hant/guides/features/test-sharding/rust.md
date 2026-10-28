---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Cargo test targets across CI workers using historical test durations."
}
---
# Rust 測試分片 {#rust-test-sharding}

Tuist 會根據歷史目標耗時，將 Cargo 測試目標分散到 CI 工作節點上。單元測試目標、整合測試目標，以及每個函式庫的文件測試（doctests）都是獨立的模組。同一個目標內的測試會保持在一起。

> [!IMPORTANT] Requirements
> - 設定<.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>，並在規劃任務與工作節點上對 CLI 進行驗證。
> - 在工作區中使用`-p <package>`選取一個套件。不支援多套件分片。
> - 在每個任務中使用相同的修訂版本、Rust 工具鏈、套件選擇、功能選項與測試篩選器。

## 建立計畫 {#create-a-plan}

在`--no-run`中加入分片數量，以便在不執行測試的情況下編譯並列舉目標：

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

該指令會輸出包含`shard_plan_id`與從零開始索引的`shards`陣列的 JSON。在 GitHub Actions 中，它也會將`shard-plan-id`與`shards`寫入`GITHUB_OUTPUT`。若未提供明確的參考識別碼，Tuist 會從支援的 CI 環境中推導出一個。

| 選項 | 說明 |
| --- | --- |
| `--shard-max N` | 最大分片數量 |
| `--shard-min N` | 最小分片數量 |
| `--shard-total N` | 精確數量，上限為可用目標數 |
| `--shard-max-duration N` | 目標最大分片持續時間（毫秒） |

單獨使用`--shard-total`，或結合`--shard-min`與`--shard-max`。若沒有歷史耗時資料，規劃器會使用預設的目標估算值。一般的`--no-run`若未帶入分片選項，仍僅為建構指令。

## 執行每個分片 {#execute-each-shard}

在每個工作節點上設定計畫 ID 與分片索引，然後使用相同的 Cargo 測試參數：

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

或者，將`TUIST_SHARD_REFERENCE`設定為規劃任務的參考識別碼，而非傳入計畫 ID。Tuist 會取得分配結果，並要求 Cargo 僅執行這些目標。無效或不相容的分配會導致指令失敗，而不會執行所有測試。空分配則不會執行任何測試。來自工作節點的結果會在 Test Insights 中連結至該計畫，且<.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantine">隔離</.localized_link>機制會在每個分片內生效。

## 限制 {#limits}

這是目標層級的分片，而非一次建構後分發。每個工作節點都需要原始碼檢出並建構自己的目标；<.localized_link href="/guides/features/cache/rust">Cargo 編譯快取</.localized_link>可以重複使用符合條件的編譯產出。Tuist 不會上傳測試執行檔，也不需要其他 Rust 測試執行器。

分片需要選取單一套件。縮減多套件指令可能會改變 Cargo 的统一依賴功能圖，因此 Tuist 會拒絕此類操作，避免以不同的功能圖執行測試。在多套件分片獲得支援之前，請分別為每個套件進行規劃。

分片需要標準的 libtest 測試框架與捕獲的預設輸出。靜默、詳細、替代格式、未捕獲輸出，以及自訂測試框架的指令都會被拒絕。如果 Cargo 無法唯一識別目標，請使用`-p <package>`選取精確的工作區套件。相依套件、版本限定選擇器、套件/目標名稱萬用字元，以及 Cargo 的夜間版`-C`選項都不支援用於分片。請確保規劃與執行階段的測試選擇保持一致。
