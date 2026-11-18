---
{
  "title": "Once 測試分片",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 規劃 Once 測試批次，將它們分配到 CI 工作節點，並檢視合併後的測試執行。"
}
---
# Once 測試分片 {#once-test-sharding}

當你的測試套件超出單一機器的負載時，Once 可以要求 Tuist 將已發現的測試批次分發到 CI 工作節點。工作節點透過 Once 執行其分配任務，而 Tuist 會將它們的報告合併為一次測試執行。

> [!IMPORTANT]
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link>。
> - 使用公開了 `once query test-plan --shards` 和 `once test --shard-plan` 的 Once 版本。Once 0.71.0 僅支援可攜式計劃，不支援此託管工作流程。
> - 對所選測試目標進行完整探索，並確保工作節點上具有相同的檢出副本和測試環境。

無需 Tuist CLI 包裝器。Once 使用其原生的 Tuist 提供者和憑證。

## 探索你的測試 {#discover-your-tests}

在規劃之前運行所選測試以建立探索：

```bash
once test MyTests --format json
```

可用的批次粒度取決於運行器。某些測試目標支援文件或案例批次；其他則保持在目標層級。請參閱[Once 的測試指南](https://buildonce.dev/docs/guide/graph/testing)以了解探索和批次功能。

## 建立託管計劃 {#create-a-hosted-plan}

在規劃作業中，使用此次 CI 執行共享的參考：

```bash
once query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

回應包含託管計劃 ID 和實際的工作節點索引：

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

根據 `shards` 建構你的 CI 矩陣，而非假設它包含四個條目。空計劃會返回空的 ID 和陣列，因此無需啟動任何工作節點。傳遞 `--target` 以縮小計劃範圍，或重複 `--changed-path` 以使用 Once 的基於圖的選擇。

參考預設為 `TUIST_SHARD_REFERENCE` 或偵測到的 CI 運行。當環境沒有支援的 CI 識別碼時，請明確傳遞它。

## 執行每個分片 {#execute-each-shard}

向每個工作節點提供返回的計劃 ID 及其自身的索引：

```bash
once test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

或者，設定 `TUIST_SHARD_PLAN_ID` 和 `TUIST_SHARD_INDEX`。工作節點下載精確綁定 UUID 的計劃，並僅執行其分配的批次。空分配不會運行任何內容；缺失的結果、失敗的程序和中斷的工作無法通過分區。

這分發的是測試計劃，而非預編譯的測試構建存檔。在工作節點上準備所需的源代碼、工具和探索；共享快取可以避免重複符合條件的構建工作。

## 重新運行和結果 {#reruns-and-results}

對於重新運行，增加 `--shard-attempt`，或設定 `TUIST_SHARD_ATTEMPT`。否則，Once 會使用 GitHub 運行嘗試次數，然後預設為 1。`--shard-report-revision` 預設為 0，並且可以在同一嘗試內修正報告時增加。這些計數器與測試的重試是分開的。

開啟**測試 → 分片**以檢查計劃、平衡和報告的工作節點，然後開啟合併的測試執行以查看個別結果。Once 的調度單元標記為**批次**；案例保留其原生的目標、套件和測試名稱。

參閱<.localized_link href="/guides/features/test-insights/once">Once 測試洞察</.localized_link>以獲取報告詳細資訊和覆蓋率限制。
