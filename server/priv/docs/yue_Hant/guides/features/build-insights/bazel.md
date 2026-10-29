---
{
  "title": "Bazel Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Bazel command duration, cache totals, and critical-path diagnostics in the Tuist dashboard."
}
---
# Bazel 構建洞察 {#bazel-build-insights}

每個已完成的 `build`、`test` 及其他 Bazel 指令都會顯示在專案的 **調用** 儀表板上：包括指令類型、退出狀態、開始和結束時間、持續時間，以及 Bazel 歸因於該次調用的快取命中、未命中、下載和上傳。

調用數據透過 Bazel 的 [Build Event Protocol](https://bazel.build/remote/bep) 傳遞。當你執行 `tuist bazel setup` 時，設定會自動為你連接；無需額外標誌即可開始查看調用。

## 儀表板顯示內容 {#what-the-dashboard-shows}

每次調用都會記錄：

- Bazel 執行的指令、其退出代碼、開始和結束時間，以及總持續時間。
- 動作、目標和套件數量。
- 有限的構建時間軸和關鍵路徑摘要。
- 歸因於該次調用的快取命中、未命中、下載和上傳。
- 在執行期間按執行順序捕獲的進度日誌行。
- Bazel 版本、git 分支和提交（當 Bazel 報告時），以及運行是否發生在 CI 上。

Bazel 無法歸因於已完成調用的快取活動（例如指令在中途被中斷），仍會以原始遠端快取觀察的形式出現在專案 **概覽** 中。這不被視為指令成功、持續時間或測試結果的證據。

## 自訂元數據 {#custom-metadata}

將鍵值數據附加到調用以比較來自不同團隊、硬體或工作流程的運行。值會顯示在每次調用的詳細頁面，並可透過應用程式介面和 Model Context Protocol 工具存取。

使用 Bazel 內建的 `--build_metadata` 標誌設定元數據：

```bash
bazel build --build_metadata=TICKET=TUIST-123 --build_metadata=RUNNER=macos-14 //...
```

或在你的 `.bazelrc` 中為每個 lane 設定一次：

```text
build:ci --build_metadata=RUNNER=macos-14
```

每次調用最多可攜帶 20 個自訂條目。鍵最多可包含 50 個字符，值最多可包含 500 個字符。超出這些限制的條目會在儲存調用之前被丟棄，因此無效條目不會阻止其餘報告被記錄。

Tuist 從構建環境衍生的上下文鍵（例如 `CI`、`GIT_BRANCH` 和 `GIT_COMMIT`）不會作為自訂值儲存，因為它們已填充調用的首要欄位。

自訂元數據對專案成員在儀表板中可見，並可透過應用程式介面和 Model Context Protocol 工具存取。請勿將其用於憑證、存取令牌或其他敏感數據。

## 選擇退出 {#opting-out}

Build Event Protocol 串流攜帶命令行參數、環境值和指令輸出。Tuist 僅保留上述已完成指令的欄位並丟棄其餘部分，但如果你根本不想發送事件串流，請重新執行設定：

```bash
tuist bazel setup --no-build-insights
```

生成的 `.bazelrc.tuist` 隨後僅設定遠端快取。調用將不再顯示在儀表板上，而快取觀察仍保留在 **概覽** 頁面。

## 數據保留 {#data-retention}

Tuist 保留 Bazel 調用及其日誌 90 天。請參閱 <.localized_link href="/guides/server/data-retention">數據保留</.localized_link> 以了解完整政策。
