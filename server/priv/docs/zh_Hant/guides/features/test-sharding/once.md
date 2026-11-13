---
{
  "title": "Once 測試分片",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 規劃 Once 測試批次，將其分散至 CI 工作節點執行，並檢視合併後的測試執行結果。"
}
---
# Once 測試分片 {#once-test-sharding}

當你的測試套件超出單一機器的負荷時，Once 可以要求 Tuist 將已發現的測試批次分散到 CI 工作節點上。工作節點透過 Once 執行其指派任務，而 Tuist 會將它們的報告合併為一次測試執行。

> [!IMPORTANT]
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link>。
> - 使用公開了 `once query test-plan --shards` 和 `once test --shard-plan` 的 Once 版本。Once 0.71.0 僅支援可攜式方案，不支援此託管工作流程。
> - 對所選測試目標進行完整探索，並確保工作節點上提供相同的檢出與測試環境。

不需要 Tuist CLI 包裝器。Once 使用其原生的 Tuist 提供者與憑證。

## 探索你的測試 {#discover-your-tests}

在規劃之前，執行所選測試以建立探索結果：

```bash
once test MyTests --format json
```

可用的批次粒度取決於執行器。某些測試目標支援檔案或案例批次；其他則維持在目標層級。請參閱[Once 的測試指南](https://buildonce.dev/docs/guide/graph/testing)以了解探索與批次功能。

## 建立託管方案 {#create-a-hosted-plan}

在規劃工作中，使用此次 CI 執行所共享的參考值：

```bash
once query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

回應包含託管方案 ID 與實際的工作節點索引：

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

根據 `shards` 建置你的 CI 矩陣，而非假設它包含四個項目。空方案會回傳空的 ID 與陣列，因此無需啟動任何工作節點。傳遞 `--target` 以縮小方案範圍，或重複使用 `--changed-path` 來採用 Once 的圖形基礎選擇。

參考值預設為 `TUIST_SHARD_REFERENCE` 或偵測到的 CI 執行。當環境中沒有受支援的 CI 識別碼時，請明確傳遞該值。

## 執行每個分片 {#execute-each-shard}

將回傳的方案 ID 與其自身索引提供給每個工作節點：

```bash
once test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

或者，設定 `TUIST_SHARD_PLAN_ID` 與 `TUIST_SHARD_INDEX`。工作節點會下載精確綁定 UUID 的方案，並僅執行其指派的批次。空指派不會執行任何內容；遺失的結果、失敗的程序與中斷的工作無法通過分割區。

這會分散測試方案，而非預編譯的測試建置封存檔。在工作節點上準備所需的原始碼、工具與探索結果；共享快取可以避免重複符合條件的建置工作。

## 重新執行與結果 {#reruns-and-results}

若要重新執行，增加 `--shard-attempt`，或設定 `TUIST_SHARD_ATTEMPT`。否則 Once 會使用 GitHub 執行嘗試次數，預設為 1。`--shard-report-revision` 預設為 0，當在同一嘗試中修正報告時可以增加。這些計數器與測試的重試次數分開。

開啟**測試 → 分片**以檢查方案、平衡與回報的工作節點，然後開啟合併的測試執行以查看個別結果。Once 的排程單位標示為**批次**；案例保留其原生的目標、套件與測試名稱。

參閱<.localized_link href="/guides/features/test-insights/once">Once 測試洞察</.localized_link>以了解報告細節與涵蓋率限制。
