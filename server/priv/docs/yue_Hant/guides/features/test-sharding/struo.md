---
{
  "title": "Struo 測試分片",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 規劃 Struo 測試批次，將其分配到 CI 工作節點，並檢視合併後的測試執行。"
}
---
# Struo 測試分片 {#struo-test-sharding}

<a id="once-test-sharding"></a>

當你的測試套件超出單一機器的負荷時，Struo 可以要求 Tuist 將已發現的測試批次分發到 CI 工作節點。工作節點透過 Struo 執行其分配任務，而 Tuist 會將它們的報告合併為一次測試執行。

> [!IMPORTANT]
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/struo-project">開始使用 Struo</.localized_link>。
> - 使用 [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 或更新版本，並搭配 `struo query test-plan --shards` 和 `struo test --shard-plan`。
> - 對所選測試目標進行完整探索，並確保工作節點上具有相同的程式碼檢出與測試環境。

不需要 Tuist CLI 包裝器。Struo 使用其原生的 Tuist 提供者與憑證。

## 探索你的測試 {#discover-your-tests}

在規劃之前，執行所選測試以建立探索結果：

```bash
struo test MyTests --format json
```

可用的批次粒度取決於執行器。部分測試目標支援檔案或案例批次；其他則維持在目標層級。請參閱 [Struo 測試指南](https://struo.run/docs/guide/graph/testing) 以了解探索與批次功能。

## 建立託管計畫 {#create-a-hosted-plan}

在規劃作業中，使用此次 CI 執行共用的參考識別碼：

```bash
struo query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

回應包含託管計畫 ID 與實際的工作節點索引：

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

根據 `shards` 建構你的 CI 矩陣，而非假設它包含四個項目。空計畫會回傳空的 ID 與陣列，因此無需啟動任何工作節點。傳遞 `--target` 以縮小計畫範圍，或重複使用 `--changed-path` 以採用 Struo 的圖形基礎選擇。

參考識別碼預設為 `TUIST_SHARD_REFERENCE` 或偵測到的 CI 執行。當環境沒有支援的 CI 識別碼時，請明確傳遞此值。

## 執行每個分片 {#execute-each-shard}

為每個工作節點提供回傳的計畫 ID 及其自身索引：

```bash
struo test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

或者，設定 `TUIST_SHARD_PLAN_ID` 和 `TUIST_SHARD_INDEX`。工作節點會下載綁定至特定 UUID 的計畫，並僅執行其分配的批次。空分配不會執行任何內容；缺少結果、程序失敗或工作中斷都無法通過分區驗證。

這會分發測試計畫，而非預編譯的測試建置封存檔。在工作節點上準備所需的原始碼、工具與探索結果；共用快取可以避免重複符合資格的建置工作。

## 重新執行與結果 {#reruns-and-results}

若要重新執行，增加 `--shard-attempt`，或設定 `TUIST_SHARD_ATTEMPT`。否則 Struo 會使用 GitHub 執行嘗試次數，預設為 1。`--shard-report-revision` 預設為 0，在同一嘗試中修正報告時可以增加。這些計數器與測試的重試機制分開。

開啟 **測試 → 分片** 以檢視計畫、負載平衡與回報的工作節點，然後開啟合併後的測試執行以查看個別結果。Struo 的排程單位標示為 **批次**；案例保留其原生的目標、套件與測試名稱。

參閱 <.localized_link href="/guides/features/test-insights/struo">Struo 測試洞察</.localized_link> 以了解報告細節與涵蓋率限制。
