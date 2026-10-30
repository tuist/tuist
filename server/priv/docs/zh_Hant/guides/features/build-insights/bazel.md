---
{
  "title": "Bazel 建置洞察",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Bazel 指令持續時間、快取總量與關鍵路徑診斷。"
}
---
# Bazel 建置洞察 {#bazel-build-insights}

每次完成的 `build`、`test` 及其他 Bazel 指令都會顯示在專案的 **叫用** 儀表板中：包含指令類型、結束狀態、開始與結束時間、持續時間，以及 Bazel 歸因於該次叫用的快取命中、未命中、下載和上傳。

叫用資料透過 Bazel 的 [Build Event Protocol](https://bazel.build/remote/bep) 傳送。當你執行 `tuist bazel setup` 時，設定會自動為你連線；無需額外旗標即可開始查看叫用。

## 儀表板顯示內容 {#what-the-dashboard-shows}

每次叫用會記錄：

- Bazel 執行的指令、其結束代碼、開始與結束時間，以及總持續時間。
- 動作、目標和套件數量。
- 有限的建置時間軸與關鍵路徑摘要。
- 歸因於該次叫用的快取命中、未命中、下載和上傳。
- 執行期間依執行順序擷取的進度紀錄行。
- Bazel 版本、Bazel 回報時的 git 分支與提交，以及該次執行是否發生在 CI 上。

Bazel 無法歸因至已完成叫用的快取活動（例如指令在中途被中斷），仍會以原始遠端快取觀察結果的形式出現在專案 **概覽** 中。這些資料不會被視為指令成功、持續時間或測試結果的證據。

## 自訂中繼資料 {#custom-metadata}

將鍵值資料附加至叫用，以便比較來自不同團隊、硬體或工作流程的執行。數值會顯示在每次叫用的詳細頁面，並可透過應用程式介面和 Model Context Protocol 工具存取。

使用 Bazel 內建的 `--build_metadata` 旗標設定中繼資料：

```bash
bazel build --build_metadata=TICKET=TUIST-123 --build_metadata=RUNNER=macos-14 //...
```

或在你的 `.bazelrc` 中為每個 lane 設定一次：

```text
build:ci --build_metadata=RUNNER=macos-14
```

每次叫用最多可攜帶 20 筆自訂項目。鍵最多可包含 50 個字元，值最多可包含 500 個字元。超出這些限制的項目會在儲存叫用前被捨棄，因此無效項目不會阻止其餘報告被記錄。

Tuist 從建置環境衍生的內容鍵（例如 `CI`、`GIT_BRANCH` 和 `GIT_COMMIT`）不會作為自訂值儲存，因為它們已填入叫用的主要欄位。

自訂中繼資料對專案成員在儀表板中可見，並可透過應用程式介面和 Model Context Protocol 工具存取。請勿將其用於憑證、存取權杖或其他敏感資料。

## 選擇退出 {#opting-out}

Build Event Protocol 串流會攜帶命令列引數、環境變數值和指令輸出。Tuist 僅保留上述已完成的指令欄位並捨棄其餘資料，但如果你完全不想傳送事件串流，請重新執行設定：

```bash
tuist bazel setup --no-build-insights
```

產生的 `.bazelrc.tuist` 隨後僅設定遠端快取。叫用將不再顯示在儀表板中，而快取觀察結果仍會保留在 **概覽** 頁面。

## 資料保留 {#data-retention}

Tuist 會保留 Bazel 叫用及其紀錄 90 天。完整政策請參閱 <.localized_link href="/guides/server/data-retention">資料保留</.localized_link>。
