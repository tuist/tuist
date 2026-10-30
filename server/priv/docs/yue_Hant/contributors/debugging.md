---
{
  "title": "偵錯",
  "titleTemplate": ":title · 貢獻者 · Tuist",
  "description": "使用編碼代理程式同本地執行來偵錯 Tuist 嘅問題。"
}
---
# 除錯 {#debugging}

開源帶來實際優勢：代碼公開可用，你可以喺本地運行，亦可以利用編碼代理更快解答問題，並除錯代碼庫中潛在嘅錯誤。

如果你喺除錯期間發現文件遺失或不完整，請更新 `docs/` 底下嘅英文文件並提交 PR。

## 喺 CI 上擷取線程轉儲 {#thread-dump-ci}

當 CLI 間歇性卡住時，你可以喺唔停止進程嘅情況下擷取線程轉儲。啟用信號處理程序，並向運行中嘅 `tuist` 進程發送 `SIGUSR1`。

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

如果未設置 `TUIST_THREAD_DUMP_SAMPLE`，處理程序會打印當前線程堆棧。輸出會寫入 stderr，因此會顯示喺 CI 日誌中。

## 使用編碼代理 {#use-coding-agents}

編碼代理有助於：

- 掃描代碼庫以找出實現特定行為嘅位置。
- 喺本地重現問題並快速迭代。
- 追蹤輸入點如何流經 Tuist 以找出根本原因。

分享你能做到嘅最小重現案例，並將代理指向特定組件（CLI、伺服器、緩存、文件或手冊）。範圍越集中，除錯過程就越快同準確。

### 常用提示詞 (FNP) {#frequently-needed-prompts}

#### 意外嘅項目生成結果 {#unexpected-project-generation}

項目生成給出咗我預期之外嘅結果。針對位於 `/path/to/project` 嘅項目運行 Tuist CLI 以了解發生此情況嘅原因。追蹤生成器流水線，並指出負責該輸出嘅代碼路徑。

#### 生成項目中可重現嘅錯誤 {#reproducible-bug-in-generated-projects}

這看起來像係生成項目中嘅一個錯誤。喺 `examples/` 底下創建一個可重現嘅項目，參考現有示例。添加一個失敗嘅驗收測試，僅選擇該測試並透過 `xcodebuild` 運行，修復問題後重新運行測試以確認通過，然後提交 PR。
