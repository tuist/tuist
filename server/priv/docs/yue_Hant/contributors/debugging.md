---
{
  "title": "偵錯",
  "titleTemplate": ":title · 貢獻者 · Tuist",
  "description": "使用編碼代理程式和本地執行來偵錯 Tuist 中的問題。"
}
---
# 偵錯 {#debugging}

開源帶來實際優勢：代碼公開，你可以喺本地運行，亦都可以用編碼代理更快解答問題，同埋調試代碼庫入面潛在嘅 bug。

如果你喺偵錯期間發現文件遺失或者不完整，請更新 `docs/` 底下嘅英文文件，並提交 PR。

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

如果無設定 `TUIST_THREAD_DUMP_SAMPLE`，處理程序會打印當前線程堆疊。輸出會寫入 stderr，因此會顯示喺 CI 日誌中。

## 使用編碼代理 {#use-coding-agents}

編碼代理有助於：

- 掃描代碼庫以找出行為實現嘅位置。
- 喺本地重現問題並快速迭代。
- 追蹤輸入點樣流經 Tuist，以找出根本原因。

分享你能做到最精簡嘅重現步驟，並引導代理關注特定組件（CLI、伺服器、快取、文件或手冊）。範圍越集中，偵錯過程就越快、越準確。

### 常用提示詞 (FNP) {#frequently-needed-prompts}

#### 意外嘅項目生成 {#unexpected-project-generation}

項目生成產生咗我預期之外嘅結果。針對位於 `/path/to/project` 嘅項目運行 Tuist CLI，以了解發生呢種情況嘅原因。追蹤生成器管道，並指出負責產生該輸出嘅代碼路徑。

#### 生成項目中可重現嘅 bug {#reproducible-bug-in-generated-projects}

這似乎係生成項目中嘅一個 bug。喺 `examples/` 底下建立一個可重現嘅項目，參考現有示例。添加一個失敗嘅驗收測試，只選擇該測試並透過 `xcodebuild` 運行，修復問題，重新運行測試以確認通過，然後提交 PR。
