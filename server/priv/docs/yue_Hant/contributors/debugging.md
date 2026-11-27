---
{
  "title": "除錯",
  "titleTemplate": ":title · 貢獻者 · Tuist",
  "description": "使用編碼代理程式同本地執行來除錯 Tuist 嘅問題。"
}
---
# 除錯 {#debugging}

開源係一個實際優勢：代碼公開，你可以喺本地運行，亦都可以用編碼代理更快咁解答問題，同埋除錯代碼庫入面潛在嘅 bug。

如果你喺除錯期間發現文件遺漏或者不完整，請更新 `server/priv/docs/en` 底下嘅英文文件，並開啟一個 PR。

## 喺 CI 上擷取執行緒傾印 {#thread-dump-ci}

當 CLI 間歇性卡住嗰陣，你可以喺唔停止程序嘅情況下擷取執行緒傾印。啟用信號處理程式，並向正在運行嘅 `tuist` 程序發送 `SIGUSR1`。

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

如果無設定 `TUIST_THREAD_DUMP_SAMPLE`，處理程式會打印當前執行緒堆疊。輸出會寫入 stderr，所以會顯示喺 CI 日誌入面。

## 使用編碼代理 {#use-coding-agents}

編碼代理有助於：

- 掃描代碼庫，搵出某個行為係喺邊度實現。
- 喺本地重現問題並快速迭代。
- 追蹤輸入點樣流經 Tuist，以搵出根本原因。

分享你能做到最細嘅重現案例，並指引代理針對特定組件（CLI、伺服器、快取、文件或手冊）。範圍越集中，除錯過程就越快同準確。

### 經常需要嘅提示 (FNP) {#frequently-needed-prompts}

#### 意外嘅項目生成 {#unexpected-project-generation}

項目生成產生咗我預期之外嘅結果。針對位於 `/path/to/project` 嘅項目運行 Tuist CLI，以了解發生呢種情況嘅原因。追蹤生成器管道，並指出負責該輸出嘅代碼路徑。

#### 已生成項目中可重現嘅 bug {#reproducible-bug-in-generated-projects}

這似乎係已生成項目中嘅一個 bug。喺 `examples/` 底下建立一個可重現嘅項目，參考現有示例。添加一個失敗嘅驗收測試，透過 `xcodebuild` 只選擇該測試來運行它，修復問題，重新運行測試以確認通過，然後開啟一個 PR。
