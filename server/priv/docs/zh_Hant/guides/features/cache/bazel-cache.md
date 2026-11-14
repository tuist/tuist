---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 在團隊與 CI 之間共用 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其作為遠端快取連線。當某個動作的輸出已存在於快取中時，Bazel 會略過該動作，並從 Tuist 的快取中提取結果，從而節省團隊與 CI 環境中的編譯時間。

## 設定 {#setup}

在 Bazel 工作區的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，並連線至最近的 Tuist 快取區域，且透過每個工作區專屬的憑證輔助程式進行驗證。它也會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

若想自行管理匯入，請傳入 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而非將其提交至版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助程式路徑，以及最接近產生該檔案之機器的快取區域，因此這些值不會轉移給團隊成員或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，因為它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案為符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。如此一來，再次執行設定具有冪等性。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板中專案的 **Bazel Cache** 頁面，顯示快取傳輸、下載與上傳、讀寫延遲、吞吐量，以及動作快取命中率。專案的 **Overview** 會摘要相同的動作快取命中率，並同時顯示建置持續時間。

若要查看某個指令如何使用快取，請從 **Invocations** 開啟它。叫用頁面會將動作快取查詢與內容物件請求分開，讓你能分辨冷動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 也能在其 Linux 執行器上執行你的 Bazel 動作，因此快取未命中時會在遠端執行，而非在本機或 CI 執行器上執行。請在設定時傳入 `--remote-execution`：

```bash
tuist bazel setup --remote-execution
```

設定隨後會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，位於遠端快取旁。每次執行時都會查找目前的執行器與映像檔，因此請重新執行設定，而非複製產生的值。動作會使用執行器的 Linux 工具鏈執行，而非你機器上安裝的工具，因此請在工作區中宣告動作所需的工具鏈。

設定也會將 `--jobs` 設為你的帳戶可同時執行的遠端動作數量的兩倍，以便每個動作都有下一個動作等待執行。若不這麼做，Bazel 會平行執行與機器核心數相同數量的動作，而一台 2 核心的 CI 執行器只會讓兩個遠端動作處於進行中。

若要使用不同的值，請在命令列上傳入 `--jobs`，或在 `try-import` 行之後的 `.bazelrc` 中設定。Bazel 會使用最後讀取到的值，因此該行前的 `--jobs` 會被產生的值取代。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會設定 Bazel 的 Build Event Service，使完成的指令出現在 **Invocations** 儀表板上。請參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel build insights</.localized_link> 以了解儀表板顯示的內容以及如何附加自訂中繼資料。

若你只想要遠端快取，而不想傳送建置事件串流，請選擇退出：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中的其中一種方法對 CI 進行驗證，然後在檢出步驟中執行一次 `tuist bazel setup`，以便 `.bazelrc.tuist` 反映執行器的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以取得針對特定供應商的範例。

## 資料保留 {#data-retention}

Tuist 會保留遠端快取觀察資料 90 天。完整政策請參閱 <.localized_link href="/guides/server/data-retention">data retention</.localized_link>。
