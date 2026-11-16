---
{
  "title": "Bazel 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist，在團隊與 CI 之間共享 Bazel 遠端快取項目。"
}
---
# Bazel 快取 {#bazel-cache}

Tuist 提供一個 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 快取，Bazel 可將其作為遠端快取連線。當動作的輸出已存在於快取中時，Bazel 會略過該動作並從 Tuist 的快取中提取結果，為你的團隊與 CI 環境節省編譯時間。如需 GitHub Actions 設定，請參閱 [Bazel on GitHub Actions](https://tuist.dev/solutions/bazel-github-actions)。如需了解遠端快取的運作方式，以及自託管快取與受管快取的比較，請參閱 [Bazel remote cache](https://tuist.dev/solutions/bazel-remote-cache)。

## 設定 {#setup}

在 Bazel 工作區的根目錄執行：

```bash
tuist bazel setup
```

這會在你的 `.bazelrc` 旁邊寫入一個 `.bazelrc.tuist` 檔案，並連線至最近的 Tuist 快取區域，透過每個工作區專屬的憑證輔助工具進行驗證。它也會在你的儲存庫的 `.bazelrc` 中加入一行 `try-import`：

```text
try-import %workspace%/.bazelrc.tuist
```

若你想自行管理匯入，請傳入 `--no-add-bazelrc-import`。

將 `.bazelrc.tuist` 加入你的 `.gitignore`，並在每台機器上執行設定，而不是將其提交至版本控制。產生的檔案會指向目前使用者的 Tuist 設定目錄下的絕對憑證輔助工具路徑，以及最接近產生該檔案之機器的快取區域，因此這兩個值都不會轉移給隊友或持續整合執行器。請在 `.bazelrc` 中提交 `try-import` 這一行，它在每台機器上都相同。

當找不到 Bazel 工作區標記、檔案為符號連結，或已設定遠端快取或 Build Event Service 時，設定會保留現有的 `.bazelrc` 不變。這樣一來，再次執行設定具有冪等性。

執行一般的 Bazel 指令以驗證整合：

```bash
bazel build //...
```

快取活動隨後會出現在 Tuist 儀表板中專案的 **Bazel Cache** 頁面，顯示快取傳輸、下載與上傳、讀取與寫入延遲、吞吐量，以及動作快取命中率。專案的 **Overview** 會提供相同的動作快取命中率摘要，並與建置持續時間一併呈現。

若要查看某個指令如何使用快取，請從 **Invocations** 開啟該項目。叫用頁面會將動作快取查詢與內容物件請求分開，讓你能區分冷啟動的動作快取與緩慢的構件下載。

## 遠端執行 {#remote-execution}

Tuist 也能在 Linux 執行器上執行你的 Bazel 動作，讓快取未命中改為在遠端執行，而非在本機或 CI 執行器上執行。已啟用的帳戶可使用遠端執行功能；請[來信聯絡我們](mailto:contact@tuist.dev)或[預約通話](https://cal.tuist.dev/team/tuist/tuist)以啟用你的帳戶。接著將 `--remote-execution` 傳入 setup：

```bash
tuist bazel setup --remote-execution
```

Setup 會在 `.bazelrc.tuist` 中將 Bazel 指向 Tuist 的執行器，與遠端快取並列。每次執行時都會查詢目前的執行器與映像檔，因此請重新執行 setup，不要複製產生的值。動作會使用執行器的 Linux 工具鏈執行，而非你本機安裝的工具，因此請在工作區中宣告動作所需的工具鏈。

Setup 也會將 `--jobs` 設為你的帳戶可同時執行的遠端動作數量的兩倍，讓每個動作都有下一個動作等待執行。若不這麼做，Bazel 會以機器核心數為上限平行執行動作，而一台 2 核心的 CI 執行器只會同時維持兩個遠端動作在執行中。

若要使用其他值，請在命令列上傳入 `--jobs`，或在 `try-import` 之後於 `.bazelrc` 中設定。Bazel 會採用最後讀取到的值，因此該行之前的 `--jobs` 會被產生的值取代。

## 建置洞察 {#build-insights}

預設情況下，`tuist bazel setup` 也會設定 Bazel 的 Build Event Service，讓已完成的命令出現在 **Invocations** 儀表板上。參閱 <.localized_link href="/guides/features/build-insights/bazel">Bazel 建置洞察</.localized_link> 以了解儀表板顯示的內容，以及如何附加自訂中繼資料。

若你只需要遠端快取，且不希望傳送建置事件串流，請使用以下選項停用：

```bash
tuist bazel setup --no-build-insights
```

## 持續整合 {#continuous-integration}

使用 <.localized_link href="/guides/server/authentication#continuous-integration">驗證指南</.localized_link> 中的其中一種方法對 CI 進行驗證，然後在 checkout 步驟中執行一次 `tuist bazel setup`，讓 `.bazelrc.tuist` 反映執行器所在的正確區域。請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以取得各供應商的具體範例。

## 資料保留 {#data-retention}

Tuist 會保留遠端快取的觀測資料 90 天。完整政策請參閱 <.localized_link href="/guides/server/data-retention">資料保留</.localized_link>。
