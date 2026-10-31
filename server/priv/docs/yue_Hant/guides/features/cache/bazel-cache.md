---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 與團隊及 CI 共用 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其連接為遠端快取。當某個動作的輸出已存在於快取中時，Bazel 會略過該動作，並從 Tuist 的快取中提取結果，從而節省團隊及 CI 環境中的編譯時間。

## 設定 {#setup}

在 Bazel workspace 的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連線至最近的 Tuist 快取區域，並透過每個 workspace 專用的憑證輔助工具進行驗證。它亦會在儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳入 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及最接近產生該檔案之機器的快取區域，因此這些值不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel workspace 標記、檔案是符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行設定就是冪等的。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會顯示在 Tuist 儀表板中專案的 **Bazel Cache** 頁面，該頁面顯示快取傳輸、下載和上傳、讀取和寫入延遲、吞吐量，以及動作快取命中率。專案 **Overview** 會連同建置持續時間，提供相同動作快取命中率的摘要。

若要查看單一指令如何使用快取，請從 **Invocations** 開啟它。調用頁面會將動作快取查找與內容物件請求分開，讓你能區分冷動作快取與緩慢的構件下載。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 亦會設定 Bazel 的 Build Event Service，使已完成的指令顯示在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 以了解儀表板顯示的內容以及如何附加自訂元數據。

如果你只想要遠端快取而不想發送建置事件串流，請使用以下選項退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的一種方法對 CI 進行驗證，然後作為檢出步驟的一部分執行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以獲取特定供應商的範例。

## 數據保留 {#data-retention}

Tuist 會保留遠端快取觀察記錄 90 天。請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link> 以了解完整政策。
