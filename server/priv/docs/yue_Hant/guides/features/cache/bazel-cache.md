---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 與你的團隊及 CI 共用 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其連接為遠端快取。當某個動作的輸出已存在於快取中時，Bazel 會略過該動作並從 Tuist 的快取拉取結果，為你的團隊及 CI 環境節省編譯時間。

## 設定 {#setup}

在 Bazel workspace 的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，連接到最近的 Tuist 快取區域，並透過每個 workspace 專用的憑證輔助程式進行驗證。它也會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

如果你想自行管理匯入，請傳遞 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交到版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助程式路徑，以及最接近產生該檔案之機器的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，它在每台機器上都相同。

當找不到 Bazel workspace 標記、檔案是符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行它是冪等的。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板中專案的 **Bazel Cache** 頁面，顯示快取傳輸、下載和上傳、讀取和寫入延遲、吞吐量，以及動作快取命中率。專案 **Overview** 會連同建構時長一起顯示相同的動作快取命中率摘要。

要查看單一指令如何使用快取，請從 **Invocations** 開啟它。叫用頁面會將動作快取查找與內容物件請求分開，讓你可以分辨冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 亦可以喺佢嘅 Linux 執行器上運行你嘅 Bazel 動作，令到快取未命中時改為遠端執行，而唔係喺本機或 CI 執行器上執行。將 `--remote-execution` 傳入 setup：

```bash
tuist bazel setup --remote-execution
```

Setup 會喺 `.bazelrc.tuist` 入面將 Bazel 指向 Tuist 嘅執行器，同遠端快取放埋一齊。每次運行時都會查找當前執行器同映像，所以請重新運行 setup，而唔好複製生成嘅數值。動作會使用執行器嘅 Linux 工具鏈運行，而唔係你部機上安裝嘅工具，因此請喺工作區中聲明你嘅動作所需嘅工具鏈。

Setup 亦會將 `--jobs` 設定為你帳戶可以同時運行嘅遠端動作數量嘅兩倍，確保每個動作都有下一個動作等候。如果唔係，Bazel 會並行運行同機器核心數量一樣多嘅動作，而一個 2 核心嘅 CI 執行器只會同時保持兩個遠端動作進行中。

要使用其他數值，請喺命令行傳遞 `--jobs`，或者喺 `try-import` 行之後喺 `.bazelrc` 中設定。Bazel 會使用最後讀取到嘅數值，所以該行之前的 `--jobs` 會被生成嘅數值取代。

## 構建洞察 {#build-insights}

預設情況下，`tuist bazel setup` 亦會配置 Bazel 嘅 Build Event Service，令已完成嘅命令顯示喺 **調用** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel 構建洞察</.localized_link> 以了解儀表板顯示嘅內容以及如何附加自訂元數據。

如果你只想要遠端快取而唔想發送構建事件流，可以使用以下選項退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">認證指南</.localized_link> 中嘅其中一種方法對 CI 進行認證，然後作為 checkout 步驟嘅一部分運行一次 `tuist bazel setup`，令 `.bazelrc.tuist` 反映執行器所屬嘅正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以獲取供應商特定嘅示例。

## 數據保留 {#data-retention}

Tuist 會保留遠端快取觀察記錄 90 日。請參閱 <.localized_link href="/guides/server/data-retention">數據保留</.localized_link> 以了解完整政策。
