---
{
  "title": "Bazel Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect flaky Bazel tests, mute their failures, and skip quarantined targets."
}
---

# Bazel 不穩定測試 {#bazel-flaky-tests}

`tuist bazel test` 會在每次調用前獲取 Tuist 的隔離政策，並將其應用於底層的 `bazel test` 運行。

## 應用隔離 {#applying-quarantine}

在測試頁面中，將其狀態更改為 **靜音**，然後運行：

```sh
tuist bazel test -- //app:tests
```

`--` 之後的參數會轉發給 `bazel test`。使用 `--path` 來選擇專案和工作目錄，並使用 `--bazel` 來選擇不同的可執行檔，例如 `bazelisk`。普通的 `bazel test` 仍會報告測試結果，但不會獲取或強制執行 Tuist 隔離政策。

隔離不需要命名的 Bazel 配置或重試。**不穩定測試**、**已隔離測試** 和個別測試頁面支援與其他構建系統相同的手動狀態更改。使用 **設定 → 自動化** 來配置不穩定性閾值、隔離操作和恢復操作。

### 靜音 {#mute}

使用 **靜音** 作為主要的隔離工作流程。被靜音的案例會繼續運行，其失敗仍然可見，而健康的同級案例仍會影響結果。新的執行提供恢復的證據，同時不排除目標中的任何案例。

Tuist 會讀取暫存的本地構建事件文件和引用的 `test.xml` 報告。僅當完整報告將每個失敗目標中報告的每個失敗歸因於靜音案例時，它才會將 Bazel 的測試失敗退出碼更改為成功。

構建錯誤、超時、中斷的運行、缺失或格式錯誤的報告、不完整的事件流，以及靜音集之外的失敗都會保留 Bazel 的失敗狀態。本地事件文件限制為 64 MiB，個別報告限制為 5 MiB。Tuist 需要自己的本地構建事件文件來驗證靜音失敗並從過時的跳過目標中恢復，因此明確的 `--build_event_json_file` 不能與活動的靜音或跳過案例結合使用。遠程構建事件報告仍透過 `tuist bazel setup` 進行配置。

原始的 Bazel 調用和報告保留其實際結果。Tuist 的伺服器會記錄案例在調用開始時是否被隔離，即使其狀態在處理報告之前發生變化。

### 跳過 {#skip}

僅在您打算排除 **整個 Bazel 目標**（包括該目標內的健康案例）時才使用 **跳過**。將單一案例標記為 **已跳過** 會產生這種針對整個目標的效果。Bazel 的個別案例過濾器語法取決於測試框架，並非普遍支援。因此，Tuist 使用啟用了測試套件擴展的本機負向目標模式。明確的目標、萬用字元選擇以及 `test_suite` 規則內的測試會保持 Bazel 的正常選擇行為。

該命令會獲取每個隔離頁面並對目標進行去重。如果 Bazel 的完整事件日誌在目標配置或執行之前識別出缺失的跳過目標，Tuist 會在警告中指出該目標，並在不含該過時排除項的情況下重試。原始請求的模式和所有其他排除項都會保留。恢復限制為五次重試；其他載入失敗和不完整的證據會保留 Bazel 的錯誤。將過時的案例返回到 **已啟用** 以永久移除其政策。直接傳遞目標模式；`--target_pattern_file` 不能與隔離排除項結合使用。如果沒有剩餘的測試目標，Bazel 會保留其正常的「未找到測試」退出狀態，這也會捕捉到意外空的測試選擇。

該命令會列印每個被排除的目標標籤，以便構建日誌顯示隔離政策排除了哪些目標（包括其健康案例）。

### 再次運行已隔離的測試 {#running-quarantined-tests-again}

若要調查或驗證修復，請繞過兩項隔離政策：

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

將案例返回到 **已啟用**，以便在後續的正常運行中包含其目標。跳過的案例在被明確包含之前不會產生新的執行，因此基於成功新運行的自動化需要在恢復它們之前進行驗證運行。

隔離檢索錯誤會在運行測試之前停止命令。該命令還會拒絕超過 20,000 個案例的政策或超過其限制大小的目標參數；它從不應用部分政策。當您故意想在不使用政策的情況下運行時，請使用 `--no-quarantine`。

## 可選配置和重試 {#optional-configuration-and-retries}

如果您的儲存庫在 `.bazelrc` 中定義了名為 `ci` 的配置，您可以使用 `--config=ci` 來選擇它：

```sh
tuist bazel test -- --config=ci //app:tests
```

這是儲存庫定義的配置，並非 Tuist 的先決條件。如果您的儲存庫未定義它，請省略該選項。

重試也是可選的，且獨立於隔離。`--flaky_test_attempts=3` 啟用每個測試最多 **三次 Bazel 總嘗試次數**，而非三次額外重試。團隊可以將其現有的重試配置保留在 `.bazelrc` 中，或明確傳遞它：

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

對於定義了 `ci` 的儲存庫，這些選項可以組合使用：

```sh
tuist bazel test -- --config=ci --flaky_test_attempts=3 //app:tests
```

## 檢測不穩定性 {#detecting-flakiness}

Tuist 使用 Bazel 的 `test.xml` 報告中的個別案例來檢測連續整合中跨重試以及同一提交和目標選擇的多次運行之間的不一致結果。本地運行仍然可見，但不會自動將測試案例標記為不穩定。當您的構建環境尚未發佈提交和分支元數據時，請提供它們：

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

必須實際運行重試，Tuist 才能觀察其結果。僅憑 Bazel 目標的不穩定摘要無法識別哪個個別案例不穩定。無法取得或無法解析的報告無法提供案例層級的證據。

案例透過目標標籤、類別名稱（回退至套件名稱）和測試名稱來識別。這使不同類別中同名方法保持分離。使用不同外部套件名稱的較舊報告會在其舊身分下保留其歷史記錄；其隔離狀態必須應用於新身分。當失敗符合基於舊套件的靜音而非其當前類別身分時，命令會警告需要重新應用哪項政策，並保持失敗阻擋狀態。政策不會自動轉移，因為多個類別可能共享舊身分。

請參閱 Bazel 的 [測試過濾器](https://bazel.build/docs/user-manual#test-filter)、[命令選項](https://bazel.build/reference/command-line-reference) 和 [構建事件描述](https://bazel.build/remote/bep-glossary) 以了解底層行為。
