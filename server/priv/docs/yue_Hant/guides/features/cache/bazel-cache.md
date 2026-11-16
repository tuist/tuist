---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 與團隊及 CI 共用 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可以將其作為遠端快取連接。當某個動作的輸出已存在於快取中時，Bazel 會跳過該動作並從 Tuist 的快取中提取結果，從而節省團隊和 CI 環境中的編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的工作原理，以及自託管快取與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄下執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連接到最近的 Tuist 快取區域，並透過每個工作區的憑證輔助工具進行驗證。它還會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳遞 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。生成的檔案指向當前使用者 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及最接近生成該檔案的機器的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 行，這在每台機器上都是相同的。

當找不到 Bazel 工作區標記、檔案是符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣，再次執行它是冪等的。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會顯示在 Tuist 儀表板中專案的 **Bazel Cache** 頁面上，其中顯示快取傳輸、下載和上傳、讀取和寫入延遲、吞吐量，以及動作快取命中率。專案 **Overview** 會提供相同動作快取命中率的摘要，以及建構持續時間。

若要查看某個指令如何使用快取，請從 **Invocations** 開啟它。叫用頁面將動作快取查找與內容物件請求分開，因此你可以區分冷動作快取和緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 亦可以在其 Linux 執行器上運行你的 Bazel 動作，因此當快取未命中時，會在遠端而非本機或 CI 執行器上執行。遠端執行功能可按帳戶請求啟用：[聯絡我們](mailto:contact@tuist.dev)以開啟此功能。啟用後，請將 `--remote-execution` 傳入 setup 指令：

```bash
tuist bazel setup --remote-execution
```

Setup 隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，該檔案與遠端快取設定並列。每次執行時，它都會查找當前的執行器和映像，因此請重新執行 setup，而不要複製生成的值。動作會使用執行器的 Linux 工具鏈運行，而非你機器上安裝的工具，因此請在工作區中聲明你的動作所需的工具鏈。

Setup 還會將 `--jobs` 設定為你帳戶可同時運行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待執行。若無此設定，Bazel 會根據機器的核心數並行運行盡可能多的動作，而一個 2 核心的 CI 執行器只能同時保持兩個遠端動作處於進行中狀態。

若要使用不同的值，請在命令行上傳入 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中進行設定。Bazel 會使用它讀取到的最後一個值，因此該行之前的 `--jobs` 會被生成的值取代。

## 構建洞察 {#build-insights}

預設情況下，`tuist bazel setup` 還會配置 Bazel 的 Build Event Service，以便已完成的命令顯示在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel 構建洞察</.localized_link> 以了解儀表板顯示的內容以及如何附加自定義元數據。

如果你只想要遠端快取而不希望發送構建事件流，可以使用以下選項退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">認證指南</.localized_link> 中的一種方法對 CI 進行認證，然後作為 checkout 步驟的一部分運行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以獲取特定供應商的範例。

## 數據保留 {#data-retention}

Tuist 會保留遠端快取觀察記錄 90 天。請參閱 <.localized_link href="/guides/server/data-retention">數據保留</.localized_link> 以了解完整政策。
