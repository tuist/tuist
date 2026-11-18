---
{
  "title": "Once 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中檢查 Once 測試套件、個別結果、失敗案例及執行時間。"
}
---
# Once 測試洞察 {#once-test-insights}

Once 會將測試結果回報給 Tuist，讓你可以追蹤本機與 CI 執行中的測試套件、調查失敗原因，並找出緩慢的測試，無須從個別工作節點收集報告。

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

Once 會串流原生測試事件，並將完成的結果發布到 Tuist 的共用測試模型。**測試**與**測試執行**會顯示各次執行；個別測試案例亦有共用的測試歷史記錄。<.localized_link href="/guides/features/test-sharding/once">託管分片執行</.localized_link>會將每個工作節點的報告合併為單一執行記錄，而不會再次計入其診斷事件串流。

## 追蹤內容 {#what-is-tracked}

- 已回報的測試目標、測試套件與個別測試案例。
- 通過、失敗與跳過的結果，並在執行器提供時包含持續時間。
- 由執行器在託管分片報告中提供的失敗訊息。
- 當測試先失敗後通過時，會記錄有序的重試嘗試與不穩定測試結果。
- 由 Once 提供的分支、提交與 CI 上下文。

測試識別使用原生的目標、套件與案例名稱。分片批次 ID 是排程單位，並非測試名稱。

一般的 `once test` 回報會保留結果與重試嘗試，但現時不會在共用測試歷史中包含失敗訊息。託管分片報告可以包含失敗訊息，但兩種回報途徑均不提供原始碼位置。請保留你的 CI 日誌，以取得 Tuist 中無法提供的診斷資訊。

並非每個測試目標都提供相同程度的細節。部分執行器會回報個別案例，其他則只回報摘要；精確到檔案或案例層級的執行是獨立功能。在依賴逐案例分析或細粒度排程之前，請參閱[Once 的測試生態系統覆蓋範圍](https://buildonce.dev/docs/guide/graph/testing#understand-current-ecosystem-coverage)。

## 不穩定測試 {#flaky-tests}

Tuist 會利用已回報的嘗試次數與 CI 歷史記錄來識別不一致的結果。回報嘗試並不等於啟用重試：請在支援重試的執行器中設定重試。請參閱<.localized_link href="/guides/features/test-insights/flaky-tests/once">Once 不穩定測試</.localized_link>以了解偵測方式與現行的隔離範圍。

## 選擇與程式碼覆蓋率 {#selection-and-code-coverage}

Once 可以使用 `--changed-path` 從其本地圖譜保守地選擇測試。這是 Once 自身的選擇機制，而非 Tuist 基於覆蓋率的託管測試選擇：

```bash
once test --changed-path src/library.rs
```

原生 Once 回報現時不會將程式碼覆蓋率上傳至 Tuist。成功的測試報告或分片計劃不會填充「程式碼覆蓋率」儀表板。

## 疑難排解 {#troubleshooting}

如果缺少某次執行記錄，請確認有效的快取提供者已命名你的 Tuist 專案，並使用 `once auth login --provider tuist` 重新認證。即時回報屬盡力而為，當回報服務不可用時，不會令原本成功的測試命令變成失敗。

執行摘要與結構化測試失敗並非完整的處理程序日誌。此伺服器現時不會擷取 Once 的原始動作日誌串流；請保留你的 CI 日誌，以取得未包含在結構化結果中的輸出。
