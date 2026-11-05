---
{
  "title": "除錯",
  "titleTemplate": ":title · 貢獻者 · Tuist",
  "description": "使用編碼代理程式同本機執行來除錯 Tuist 嘅問題。"
}
---
# 偵錯 {#debugging}

開源帶來實際優勢：你可以取得原始碼、在本地執行，並利用編碼代理更快解答疑問，以及偵錯代碼庫中的潛在錯誤。

如果你在偵錯時發現文件遺漏或不完整，請更新 `docs/` 底下的英文文件並提交 PR。

## 在 CI 上擷取線程轉儲 {#thread-dump-ci}

當 CLI 偶爾停滯時，你可以在不停止程序的情況下擷取線程轉儲。啟用信號處理程式，並向正在執行的 `tuist` 程序發送 `SIGUSR1`。

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

如果未設定 `TUIST_THREAD_DUMP_SAMPLE`，處理程式會印出當前線程堆疊。輸出會寫入 stderr，因此會出現在 CI 日誌中。

## 使用編碼代理 {#use-coding-agents}

編碼代理有助於：

- 掃描代碼庫以找出實作特定行為的位置。
- 在本地重現問題並快速迭代。
- 追蹤輸入如何流經 Tuist 以找出根本原因。

盡可能分享最小的重現案例，並將代理指向特定元件（CLI、伺服器、快取、文件或手冊）。範圍越集中，偵錯過程就越快速且準確。

### 常用提示詞 (FNP) {#frequently-needed-prompts}

#### 專案生成結果不符合預期 {#unexpected-project-generation}

專案生成給我的結果不符合預期。針對位於 `/path/to/project` 的專案執行 Tuist CLI，以了解發生此情況的原因。追蹤生成器管線，並指出負責產生該輸出的代碼路徑。

#### 已生成專案中的可重現錯誤 {#reproducible-bug-in-generated-projects}

這看起來像是已生成專案中的錯誤。在 `examples/` 底下建立一個可重現的專案，並參考現有範例。新增一個會失敗的驗收測試，透過 `xcodebuild` 僅執行該測試來修復問題，重新執行測試以確認通過，然後提交 PR。
