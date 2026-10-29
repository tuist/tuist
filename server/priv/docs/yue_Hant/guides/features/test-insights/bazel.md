---
{
  "title": "Bazel Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Bazel test analytics in the Tuist dashboard to monitor test performance and reliability."
}
---
# Bazel 測試洞察 {#bazel-test-insights}

透過 Tuist 執行 Bazel 測試，以將數據提供給與其他建構系統相同的測試儀表板：

```bash
tuist bazel test -- //app:tests
```

`--` 之後的引數會轉發至 `bazel test`。使用 `--path` 來選擇專案和工作目錄，並使用 `--bazel` 來選擇不同的可執行檔，例如 `bazelisk`。一般的 `bazel test` 仍然會報告測試結果，但不會抓取或強制執行 Tuist 隔離政策。

> [!NOTE]
> `tuist bazel test` 包裝器僅適用於 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">已隔離的測試</.localized_link>。常規測試執行的每個案例報告由 `tuist bazel setup` 在 `.bazelrc.tuist` 中設定，因此單純的 `bazel test` 也會報告個別案例。

## 追蹤內容 {#what-is-tracked}

Tuist 會解析 `test.xml` 報告並擷取 Bazel 為每個測試目標產生的 `test.log` 輸出，然後將它們匯總到共用的測試執行模型中。每次執行會記錄：

- 個別測試案例的通過、失敗和跳過狀態，以及持續時間。
- 測試目標、類別和套件結構。
- 當 Bazel 設定為重試不穩定測試時的重試嘗試。
- 從目標的 `test.log` 擷取的失敗輸出。

**測試執行**、**測試案例** 和個別測試頁面對於 Bazel 的運作方式與其他建構系統相同。

## 產生每個案例的 JUnit 報告 {#per-case-junit-reports}

每個案例的資料列取決於測試目標是否在 Bazel 提供的 `$XML_OUTPUT_FILE` 路徑寫入 JUnit `test.xml`。當執行器未寫入時，Bazel 會回退到以目標命名的合成單一案例報告，而 Tuist 會顯示每個目標的單一資料列（在測試案例清單中标記為 **Bazel 目標**），原始的 `test.log` 仍可在執行頁面上查看。

大多數 Bazel 測試規則已經產生真實的 `test.xml`：

- `java_test` 和 `kt_jvm_test`：內建 JUnit。
- 搭配 GoogleTest 的 `cc_test`：當針對較新的 gtest 編譯時，執行器會寫入 JUnit；較舊的設定需要 `--gtest_output=xml:$XML_OUTPUT_FILE`。
- `py_test`：使用帶有 `--junitxml=$XML_OUTPUT_FILE` 的 pytest，或使用 `rules_python` pytest 執行器。
- `go_test`：將 `go test -json` 導管傳輸至 `gotestsum --junitfile=$XML_OUTPUT_FILE`，或使用發出 JUnit 的輔助工具進行包裝。

來自 `rules_rust` 和 `rules_rs` 的 `rust_test` 執行標準 `libtest` 測試框架，這在穩定版 Rust 上不會寫入 JUnit。使用腳本包裝測試目標以解析 `libtest` 輸出並將 JUnit 寫入 `$XML_OUTPUT_FILE`；這樣你可以在 Tuist 中保留每個案例的資料列，且同一個執行仍保持為單一的 Bazel 測試目標。

## 測試身分識別 {#test-identity}

案例透過目標標籤、類別名稱（若無則回退至套件名稱）和測試名稱來識別。這使得不同類別中同名方法得以區分。使用不同外層套件名稱的舊報告會在其舊身分識別下保留歷史記錄；套用於舊身分識別的狀態變更需要重新套用到新身分識別，且當失敗符合舊身分識別時，命令會警告你，以便你知道要移動哪項政策。

## 提供 CI 上下文 {#providing-ci-context}

Tuist 從 Bazel 的建構元數據讀取 git 提交和分支資訊，以便比較不同環境中相同提交的執行結果。大多數持續整合系統已設定這些資訊；如果你的系統沒有，請明確傳遞：

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

相同的 `--build_metadata` 標誌正是 <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel 建構洞察</.localized_link> 頁面所述用於標記呼叫的方式，因此一組標誌即可涵蓋這兩個介面。

## 不穩定測試與隔離 {#flaky-tests-and-quarantine}

重試、跨執行不穩定性檢測以及每個案例的隔離（靜音和跳過）均可透過 `tuist bazel test` 運作。請參閱 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel 不穩定測試</.localized_link> 以了解完整工作流程。

## 數據保留 {#data-retention}

Tuist 會保留產生測試執行的 Bazel 呼叫、其日誌以及待處理的測試攝取記錄達 90 天。測試案例及其執行歷史使用與其他建構系統相同的模型，不受該時間窗口限制。請參閱 <.localized_link href="/guides/server/data-retention">數據保留</.localized_link> 以了解完整政策。
