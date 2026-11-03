---
{
  "title": "Bazel 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Bazel 測試分析數據，以監察測試效能與可靠性。"
}
---
# Bazel 測試分析 {#bazel-test-insights}

透過 Tuist 執行 Bazel 測試，將資料餵入與其他建構系統相同的測試儀表板：

```bash
tuist bazel test -- //app:tests
```

`--` 之後的引數會轉發給 `bazel test`。使用 `--path` 選擇專案與工作目錄，並使用 `--bazel` 選擇不同的可執行檔（例如 `bazelisk`）。一般的 `bazel test` 仍會回報測試結果，但不會擷取或強制執行 Tuist 隔離政策。

> [!NOTE]
> `tuist bazel test` 包裝器只對 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">被隔離的測試</.localized_link>是必需的。常規測試執行的逐案例回報由 `tuist bazel setup` 在 `.bazelrc.tuist` 中設定，因此單純的 `bazel test` 也會回報個別案例。

## 追蹤內容 {#what-is-tracked}

Tuist 會解析 `test.xml` 報告，並擷取 Bazel 為每個測試目標產生的 `test.log` 輸出，然後將其匯總至共用的測試執行模型。每次執行會記錄：

- 個別測試案例的通過、失敗和略過狀態，以及持續時間。
- 測試目標、類別與套件結構。
- 當 Bazel 設定為重試不穩定測試時的重試次數。
- 從目標的 `test.log` 擷取的失敗輸出。

**測試執行**、**測試案例** 與個別測試頁面在 Bazel 上的運作方式，與其他建構系統相同。

## 產生逐案例 JUnit 報告 {#per-case-junit-reports}

逐案例資料列取決於測試目標是否在 Bazel 提供的 `$XML_OUTPUT_FILE` 路徑寫入 JUnit `test.xml`。當執行器未寫入時，Bazel 會退回為以目標命名的合成單一案例報告，而 Tuist 會在「測試案例」清單中為每個目標顯示單一資料列（標示為 **Bazel 目標**），原始 `test.log` 仍可在執行頁面取得。

大多數 Bazel 測試規則已會產生真正的 `test.xml`：

- `java_test` 與 `kt_jvm_test`：內建 JUnit。
- 搭配 GoogleTest 的 `cc_test`：當針對較新版本的 gtest 編譯時，執行器會寫入 JUnit；較舊的設定需要 `--gtest_output=xml:$XML_OUTPUT_FILE`。
- `py_test`：使用帶有 `--junitxml=$XML_OUTPUT_FILE` 的 pytest，或使用 `rules_python` pytest 執行器。
- `go_test`：將 `go test -json` 透過 `gotestsum --junitfile=$XML_OUTPUT_FILE` 管線處理，或以輔助工具包裝以產生 JUnit。

來自 `rules_rust` 與 `rules_rs` 的 `rust_test` 會執行標準的 `libtest` 測試框架，該框架在穩定版 Rust 上不會寫入 JUnit。請以腳本包裝測試目標，解析 `libtest` 輸出並將 JUnit 寫入 `$XML_OUTPUT_FILE`；這樣可在 Tuist 中保留逐案例資料列，而同一次執行仍維持為單一 Bazel 測試目標。

## 測試身分識別 {#test-identity}

案例以目標標籤、類別名稱（若無則回退至套件名稱）與測試名稱來識別。這能確保不同類別中同名方法保持獨立。使用不同外層套件名稱的舊報告會以舊身分識別保留其歷史紀錄；套用於舊身分識別的狀態變更需要重新套用到新身分識別，而命令會在失敗符合舊身分識別時發出警告，讓你知道應遷移哪項政策。

## 提供 CI 脈絡 {#providing-ci-context}

Tuist 會從 Bazel 的建構中繼資料讀取 Git 提交與分支資訊，以便跨環境比較同一提交的執行。大多數持續整合系統已設定這些資訊；若你的系統沒有，請明確傳遞：

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

相同的 `--build_metadata` 旗標正是 <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel 建構分析</.localized_link> 頁面所述用於標記叫用的方式，因此一組旗標即可涵蓋兩個介面。

## 不穩定測試與隔離 {#flaky-tests-and-quarantine}

重試、跨執行不穩定偵測，以及逐案例隔離（靜音與略過）皆可透過 `tuist bazel test` 運作。完整工作流程請參閱 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel 不穩定測試</.localized_link>。

## 資料保留 {#data-retention}

Tuist 會保留產生測試執行的 Bazel 叫用、其日誌，以及待處理的測試擷取記錄 90 天。測試案例及其執行歷史使用與其他建構系統相同的模型，不受該時間範圍限制。完整政策請參閱 <.localized_link href="/guides/server/data-retention">資料保留</.localized_link>。
