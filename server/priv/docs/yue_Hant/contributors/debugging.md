---
{
  "title": "除錯",
  "titleTemplate": ":title · 貢獻者 · Tuist",
  "description": "使用編碼代理程式同本地執行嚟除錯 Tuist 嘅問題。"
}
---
# 除錯 {#debugging}

開源帶來實際優勢：代碼公開，你可以本機運行，並使用編碼代理更快解答疑問、除錯代碼庫中的潛在錯誤。

如果你在除錯時發現文件遺漏或不完整，請更新 `server/priv/docs/en` 下的英文文件並提交 PR。

## 在 CI 上擷取執行緒傾印 {#thread-dump-ci}

當 CLI 間歇性卡住時，你可以在不停止程序的情況下擷取執行緒傾印。啟用信號處理程式，並向正在運行的 `tuist` 程序發送 `SIGUSR1`。

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

如果未設定 `TUIST_THREAD_DUMP_SAMPLE`，處理程式會列印當前執行緒堆疊。輸出會寫入 stderr，因此會出現在 CI 日誌中。

## 使用編碼代理 {#use-coding-agents}

編碼代理有助於：

- 掃描代碼庫以找出行為實作的位置。
- 在本機重現問題並快速迭代。
- 追蹤輸入如何流經 Tuist 以找出根本原因。

分享你能提供的最小重現案例，並將代理指向特定組件（CLI、伺服器、快取、文件或手冊）。範圍越聚焦，除錯過程就越快速準確。

### 常用提示詞 (FNP) {#frequently-needed-prompts}

#### 意外的項目生成 {#unexpected-project-generation}

項目生成給出了我不預期的結果。針對位於 `/path/to/project` 的我的項目運行 Tuist CLI，以了解發生此情況的原因。追蹤生成器管道並指出負責輸出的代碼路徑。

#### 已生成項目中的可重現錯誤 {#reproducible-bug-in-generated-projects}

這看起來像是已生成項目中的錯誤。在 `examples/` 下建立一個可重現的項目，參考現有範例。新增一個失敗的驗收測試，僅選擇該測試並透過 `xcodebuild` 運行，修復問題後重新運行測試以確認通過，然後提交 PR。
