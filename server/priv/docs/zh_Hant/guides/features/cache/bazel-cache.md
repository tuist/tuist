---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist，在團隊與 CI 之間共用 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其作為遠端快取連接。當動作的輸出已存在於快取中時，Bazel 會跳過該動作並從 Tuist 的快取中提取結果，為你的團隊和 CI 環境節省編譯時間。如需搭配快取與遠端執行的 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。

## 設定 {#setup}

在 Bazel 工作區的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連線至最近的 Tuist 快取區域，並透過每個工作區專屬的憑證輔助程式進行驗證。它也會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳入 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助程式路徑，以及最接近產生該檔案之機器的快取區域，因此這些值不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案是符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行就是冪等的。

執行一般的 Bazel 指令來驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板專案的 **Bazel Cache** 頁面上，顯示快取傳輸、下載和上傳、讀寫延遲、吞吐量以及動作快取命中率。專案 **Overview** 會提供相同的動作快取命中率摘要，並列顯示建置持續時間。

若要查看某個指令如何使用快取，請從 **Invocations** 開啟它。叫用頁面會將動作快取查詢與內容物件請求分開，讓你能夠分辨冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 也可以在其 Linux 執行器上執行你的 Bazel 動作，因此快取未命中會在遠端執行，而不是在本機機器或 CI 執行器上執行。請將 `--remote-execution` 傳入設定：

```bash
tuist bazel setup --remote-execution
```

設定隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，位於遠端快取旁邊。每次執行時都會查找目前的執行器和映像檔，因此請重新執行設定，而不是複製產生的值。動作使用執行器的 Linux 工具鏈執行，而非你機器上安裝的工具，因此請在工作區中宣告你的動作所需的工具鏈。

設定也會將 `--jobs` 設為你的帳戶一次可執行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待執行。若無此設定，Bazel 會平行執行與機器核心數一樣多的動作，而雙核心 CI 執行器只會讓兩個遠端動作處於執行中狀態。

若要使用不同的值，請在命令列上傳入 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定。Bazel 會使用它讀取的最後一個值，因此該行之前的 `--jobs` 會被產生的值取代。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會設定 Bazel 的 Build Event Service，以便已完成的指令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 以了解儀表板顯示的內容以及如何附加自訂中繼資料。

如果你只想要遠端快取而不想傳送建置事件串流，請選擇退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的其中一種方法對 CI 進行驗證，然後在檢出步驟中執行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以取得特定供應商的範例。

## 資料保留 {#data-retention}

Tuist 會保留遠端快取觀察資料 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 以了解完整政策。
