---
{
  "title": "Once 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中檢視 Once 測試套件、個別結果、失敗項目與執行時間。"
}
---
# Once 測試洞察 {#once-test-insights}

Once 會將測試結果回報給 Tuist，讓你能夠追蹤本機與 CI 執行中的測試套件、調查失敗原因，並找出緩慢的測試，無須從個別工作節點收集報告。

> [!IMPORTANT]
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link>。
> - 使用能回報結構化結果的測試目標。可用的詳細程度取決於目標類型與測試執行器。

## 回報你的測試執行 {#report-your-test-runs}

執行整個測試套件或選擇特定目標：

```bash
once test
once test MyTests
```

Once 會串流原生測試事件，並將完成的結果發布至 Tuist 的共用測試模型。**測試**與**測試執行**會顯示各次執行；個別測試案例也有共用的測試歷史記錄。<.localized_link href="/guides/features/test-sharding/once">託管分片執行</.localized_link>會將每個工作節點的報告合併為單一執行記錄，而非再次計入其診斷事件串流。

## 追蹤內容 {#what-is-tracked}

- 已回報的測試目標、測試套件與個別測試案例。
- 通過、失敗與跳過的結果，並在執行器提供時包含持續時間。
- 由執行器在託管分片報告中提供的失敗訊息。
- 當測試先失敗後通過時，會記錄有序的重試嘗試與不穩定測試結果。
- 由 Once 提供的分支、提交與 CI 上下文。

測試識別使用原生的目標、套件與案例名稱。分片批次 ID 是排程單位，並非測試名稱。

一般的 `once test` 回報會保留結果與重試嘗試，但目前在共用測試歷史記錄中不包含失敗訊息。託管分片報告可以包含失敗訊息，但兩種回報路徑皆不提供原始碼位置。請保留你的 CI 日誌，以取得 Tuist 中無法提供的診斷資訊。

並非每個測試目標都提供相同程度的詳細資訊。有些執行器會回報個別案例，有些則僅提供摘要；精確到檔案或案例層級的執行是獨立的功能。在依賴逐案例分析或細粒度排程之前，請參閱[Once 的測試生態系覆蓋範圍](https://buildonce.dev/docs/guide/graph/testing#understand-current-ecosystem-coverage)。

## 不穩定測試 {#flaky-tests}

Tuist 會利用回報的嘗試次數與 CI 歷史記錄來識別不一致的結果。回報嘗試並不等於啟用重試：請在支援重試的執行器中設定重試。請參閱<.localized_link href="/guides/features/test-insights/flaky-tests/once">Once 不穩定測試</.localized_link>以了解偵測方式與目前的隔離邊界。

## 選擇與程式碼涵蓋率 {#selection-and-code-coverage}

Once 可以使用 `--changed-path` 從其本機圖表中保守地選擇測試。這是 Once 自身的選擇機制，並非 Tuist 基於涵蓋率的託管測試選擇：

```bash
once test --changed-path src/library.rs
```

原生的 Once 回報目前不會將程式碼涵蓋率上傳至 Tuist。成功的測試報告或分片計畫不會填充「程式碼涵蓋率」儀表板。

## 疑難排解 {#troubleshooting}

如果缺少某次執行記錄，請確認有效的快取提供者已命名你的 Tuist 專案，並使用 `once auth login --provider tuist` 重新驗證。即時回報採盡力而為原則，當回報服務不可用时，不會將原本成功的測試命令轉為失敗。

執行摘要與結構化測試失敗並非完整的程序日誌。此伺服器目前不會接收 Once 的原始動作日誌串流；請保留你的 CI 日誌，以取得未包含在結構化結果中的輸出。
