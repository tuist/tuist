---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 與團隊及 CI 共用 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其連接為遠端快取。當動作的輸出已存在於快取中時，Bazel 會跳過該動作並從 Tuist 的快取中提取結果，從而節省團隊及 CI 環境中的編譯時間。如需設定帶有快取和遠端執行的 GitHub Actions，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。

## 設定 {#setup}

從 Bazel workspace 的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連接到最近的 Tuist 快取區域，並透過每個 workspace 專屬的憑證輔助工具進行驗證。它還會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳遞 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。生成的檔案指向當前用戶 Tuist 配置目錄下的絕對憑證輔助工具路徑，以及最接近生成該檔案的機器的快取區域，因此這些值不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 行，因為它在每台機器上都是相同的。

當找不到 Bazel workspace 標記、檔案是符號連結，或已配置遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣，再次執行它是冪等的。

執行正常的 Bazel 命令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板專案的 **Bazel Cache** 頁面中，顯示快取傳輸、下載和上傳、讀寫延遲、吞吐量以及動作快取命中率。專案 **Overview** 會連同建置持續時間一起顯示相同的動作快取命中率摘要。

若要查看某個命令如何使用快取，請從 **Invocations** 開啟它。調用頁面將動作快取查找與內容物件請求分開，以便你可以區分冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 還可以在其 Linux 執行器上運行你的 Bazel 動作，因此快取未命中會在遠端而非本地機器或 CI 執行器上運行。將 `--remote-execution` 傳遞給設定：

```bash
tuist bazel setup --remote-execution
```

設定隨後在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，位於遠端快取旁邊。它每次運行時都會查找當前執行器和映像，因此請重新運行設定而不是複製生成的值。動作使用執行器的 Linux 工具鏈運行，而不是你機器上安裝的工具，因此請在 workspace 中聲明你的動作所需的工具鏈。

設定還會將 `--jobs` 設置為你的帳戶可以同時運行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待執行。否則，Bazel 會并行運行與機器核心數一樣多的動作，而 2 核心的 CI 執行器只能保持兩個遠端動作處於執行狀態。

若要使用不同的值，請在命令行傳遞 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設置它。Bazel 使用它讀取的最後一個值，因此該行之前的 `--jobs` 會被生成的值替換。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 還會配置 Bazel 的 Build Event Service，以便完成的命令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 了解儀表板顯示的內容以及如何附加自定義元數據。

如果你只想要遠端快取而不希望發送建置事件流，請選擇退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一種方法對 CI 進行身份驗證，然後作為 checkout 步驟的一部分運行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 獲取特定提供商的範例。

## 數據保留 {#data-retention}

Tuist 保留遠端快取觀察數據 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 了解完整政策。
