---
{
  "title": "Bazel 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "偵測 Bazel 不穩定測試、靜音其失敗，並跳過已隔離的目標。"
}
---

# Bazel 不穩定測試 {#bazel-flaky-tests}

`tuist bazel test` 會在每次調用前獲取 Tuist 的隔離政策，並將其應用於底層的 `bazel test` 運行。

## 應用隔離 {#applying-quarantine}

在測試頁面中，將其狀態更改為 **靜音**，然後運行：

```sh
tuist bazel test -- //app:tests
```

`--` 之後的參數會轉發給 `bazel test`。使用 `--path` 選擇項目和工作目錄，並使用 `--bazel` 選擇不同的可執行文件，例如 `bazelisk`。普通的 `bazel test` 仍然會報告測試結果，但不會獲取或強制執行 Tuist 隔離政策。

隔離不需要命名的 Bazel 配置或重試。**不穩定測試**、**已隔離測試** 和單獨的測試頁面支持與其他構建系統相同的手動狀態更改。使用 **設置 → 自動化** 來配置不穩定性閾值、隔離操作和恢復操作。

### 靜音 {#mute}

使用 **靜音** 作為主要的隔離工作流程。被靜音的用例會繼續運行，其失敗仍然可見，健康的兄弟用例仍然會影響結果。新的執行提供恢復證據，而不會從目標中排除任何用例。

Tuist 讀取一個臨時的本地構建事件文件和引用的 `test.xml` 報告。僅當完整報告將每個失敗目標中報告的每個失敗歸因於一個靜音用例時，它才會將 Bazel 的測試失敗退出更改為成功。

構建錯誤、超時、中斷的運行、缺失或格式錯誤的報告、不完整的事件流以及靜音集之外的失敗都會保留 Bazel 的失敗狀態。本地事件文件限制為 64 MiB，單個報告限制為 5 MiB。Tuist 需要自己的本地構建事件文件來驗證靜音失敗並從過時的跳過目標中恢復，因此顯式的 `--build_event_json_file` 不能與活動的靜音或跳過用例結合使用。遠程構建事件報告仍通過 `tuist bazel setup` 進行配置。

原始的 Bazel 調用和報告保留其實際結果。Tuist 的服務器記錄用例在調用開始時是否被隔離，即使其狀態在處理報告之前發生變化。

### 跳過 {#skip}

僅當你打算排除 **整個 Bazel 目標**（包括該目標內的健康用例）時，才使用 **跳過**。將單個用例標記為 **已跳過** 會產生這種目標範圍的影響。Bazel 的單個用例過濾器語法取決於測試框架，並非普遍支持。因此，Tuist 使用啟用了測試套件擴展的本機負目標模式。顯式目標、通配符選擇和 `test_suite` 規則內的測試保留 Bazel 的正常選擇行為。

該命令獲取每個隔離頁面並對目標進行去重。如果 Bazel 的完整事件日誌在目標配置或執行之前識別出缺失的跳過目標，Tuist 會在警告中指出該目標，並在沒有該過時排除的情況下重試。原始請求的模式和所有其他排除項都會保留。恢復限制為五次重試；其他加載失敗和不完整的證據保留 Bazel 的錯誤。將過時的用例返回到 **已啟用** 以永久刪除其政策。直接傳遞目標模式；`--target_pattern_file` 不能與隔離排除項結合使用。如果沒有剩餘的測試目標，Bazel 將保留其正常的“未找到測試”退出狀態，這也會捕獲意外空的測試選擇。

該命令打印每個排除的目標標籤，以便構建日誌顯示隔離政策排除了哪些目標，包括它們的健康用例。

### 再次運行已隔離的測試 {#running-quarantined-tests-again}

要調查或驗證修復，請繞過兩個隔離政策：

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

將用例返回到 **已啟用** 以將其目標包含在後續的正常運行中。跳過的用例在明確包含之前不會產生新的執行，因此基於成功新運行的自動化需要在恢復它們之前進行驗證運行。

隔離檢索錯誤會在運行測試之前停止命令。該命令還會拒絕超過 20,000 個用例的政策或超過其邊界大小的目標參數；它從不應用部分政策。當你故意想在沒有政策的情況下運行時，使用 `--no-quarantine`。

## 可選配置和重試 {#optional-configuration-and-retries}

如果你的存儲庫在 `.bazelrc` 中定義了一個名為 `ci` 的配置，你可以使用 `--config=ci` 選擇它：

```sh
tuist bazel test -- --config=ci //app:tests
```

這是一個存儲庫定義的配置，不是 Tuist 的先決條件。當你的存儲庫未定義它時，省略該選項。

重試也是可選的，並且獨立於隔離。`--flaky_test_attempts=3` 啟用每個測試最多 **三次 Bazel 嘗試**，而不是三次額外重試。團隊可以將現有的重試配置保留在 `.bazelrc` 中或顯式傳遞：

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

對於定義了 `ci` 的存儲庫，可以組合這些選項：

```sh
tuist bazel test -- --config=ci --flaky_test_attempts=3 //app:tests
```

## 檢測不穩定性 {#detecting-flakiness}

Tuist 使用 Bazel 的 `test.xml` 報告中的單個用例來檢測跨重試以及持續集成中相同提交和目標選擇的運行之間的不一致結果。本地運行仍然可見，但不會自動將測試用例標記為不穩定。當你的構建環境尚未發布提交和分支元數據時，請提供它們：

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

必須實際運行重試，Tuist 才能觀察其結果。僅憑 Bazel 目標的不穩定摘要無法識別哪個單個用例不穩定。不可用或無法解析的報告無法提供用例級別的證據。

用例由目標標籤、類名（回退到套件名稱）和測試名稱標識。這使得不同類中同名方法保持分離。使用不同封裝套件名稱的舊報告在舊身份下保留其歷史記錄；它們的隔離狀態必須應用於新身份。當失敗匹配基於舊套件的靜音而不是其當前類身份時，命令會警告需要重新應用哪個政策並保持失敗阻塞。政策不會自動轉移，因為多個類可能共享舊身份。

參閱 Bazel 的 [測試過濾器](https://bazel.build/docs/user-manual#test-filter)、[命令行選項](https://bazel.build/reference/command-line-reference) 和 [構建事件描述](https://bazel.build/remote/bep-glossary) 以了解底層行為。
