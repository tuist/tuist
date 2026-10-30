---
{
  "title": "Rust 測試分片",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "根據歷史測試耗時，將 Cargo 測試目標分派到 CI 工作節點。"
}
---
# Rust 測試分片 {#rust-test-sharding}

Tuist 會根據歷史目標耗時，將 Cargo 測試目標分配到 CI 工作節點。單元測試目標、整合測試目標，以及每個函式庫的文件測試（doctests）都是獨立模組。同一個目標內的測試會保持在一起。

> [!IMPORTANT] Requirements
> - 設定 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>，並在規劃任務和工作節點上驗證 CLI。
> - 在工作區中使用 `-p <package>` 選擇一個套件。不支援多套件分片。
> - 在每個任務中使用相同的修訂版本、Rust 工具鏈、套件選擇、功能選項和測試篩選器。

## 建立計劃 {#create-a-plan}

在 `--no-run` 中加入分片數量，以編譯並列舉目標而不執行測試：

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

指令會輸出包含 `shard_plan_id` 和從零開始的 `shards` 陣列的 JSON。在 GitHub Actions 中，它也會將 `shard-plan-id` 和 `shards` 寫入 `GITHUB_OUTPUT`。如果沒有明確指定參考值，Tuist 會從支援的 CI 環境中推導出一個。

| 選項 | 說明 |
| --- | --- |
| `--shard-max N` | 最大分片數量 |
| `--shard-min N` | 最小分片數量 |
| `--shard-total N` | 精確數量，最多為可用目標數 |
| `--shard-max-duration N` | 目標最大分片持續時間（毫秒） |

單獨使用 `--shard-total`，或結合 `--shard-min` 和 `--shard-max`。如果沒有歷史耗時數據，規劃器會使用預設的目標估算值。普通的 `--no-run` 若不含分片選項，則仍為僅編譯指令。

## 執行每個分片 {#execute-each-shard}

在每個工作節點上設定計劃 ID 和分片索引，然後使用相同的 Cargo 測試參數：

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

或者，將 `TUIST_SHARD_REFERENCE` 設定為規劃任務的參考值，而不是傳遞計劃 ID。Tuist 會獲取分配結果，並要求 Cargo 只執行那些目標。無效或不兼容的分配會導致指令失敗，而不會執行所有測試。空分配不會執行任何測試。來自工作節點的結果會在 Test Insights 中連結到計劃，且 <.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantine">隔離</.localized_link> 會在每個分片內適用。

## 限制 {#limits}

這是目標層級的分片，而非一次建構分發。每個工作節點都需要原始碼檢出並建構自己的目標；<.localized_link href="/guides/features/cache/rust">Cargo 編譯快取</.localized_link> 可以重用符合條件的編譯輸出。Tuist 不會上傳測試可執行檔，也不需要其他 Rust 測試執行器。

分片需要選擇一個套件。縮小多套件指令的範圍可能會改變 Cargo 的統一依賴功能，因此 Tuist 會拒絕此操作，而不是使用不同的功能圖執行測試。在支援多套件分片之前，請分別規劃每個套件。

分片需要標準的 libtest 測試框架和捕獲的預設輸出。靜默、詳細、替代格式、未捕獲輸出和自訂框架指令會被拒絕。如果 Cargo 無法唯一識別目標，請使用 `-p <package>` 選擇確切的工作區套件。依賴套件、版本限定選擇器、套件/目標名稱萬用字元，以及 Cargo 的 nightly `-C` 選項不支援用於分片。請確保規劃和執行之間的測試選擇保持一致。
