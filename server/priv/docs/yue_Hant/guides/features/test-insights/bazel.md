---
{
  "title": "Bazel 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Bazel 測試分析數據，以監察測試效能與可靠性。"
}
---
# Bazel 測試洞察 {#bazel-test-insights}

> [!IMPORTANT]
> **要求**
>
> - 透過 `tuist bazel setup` 連接的 Bazel 工作區，詳情請參閱 <.localized_link href="/guides/get-started/bazel-project">開始使用 Bazel 專案</.localized_link>。

`tuist bazel setup` 會在 `.bazelrc.tuist` 中設定每個案例的報告，因此一般的 `bazel test` 會將個別測試案例回報至與其他建構系統相同的儀表板：

```bash
bazel test //app:tests
```

如要同時套用 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">隔離</.localized_link>，請改為透過 Tuist 包裝器執行測試。`--` 之後的引數會轉發至 `bazel test`：

```bash
tuist bazel test -- //app:tests
```

## 追蹤內容 {#what-is-tracked}

Tuist 會剖析 `test.xml` 報告並擷取 Bazel 為每個測試目標產生的 `test.log` 輸出，然後將其彙整至共用的測試執行模型。每次執行會記錄：

- 個別測試案例的通過、失敗和略過狀態，以及持續時間。
- 測試目標、類別和套件結構。
- 當 Bazel 設定為重試不穩定測試時的重試嘗試。
- 從目標的 `test.log` 擷取的失敗輸出。

**測試執行**、**測試案例** 和個別測試頁面在 Bazel 上的運作方式與其他建構系統相同。

## 產生每個案例的 JUnit 報告 {#per-case-junit-reports}

每個案例的資料列取決於測試目標是否在 Bazel 提供的 `$XML_OUTPUT_FILE` 路徑寫入 JUnit `test.xml`。當執行器未寫入時，Bazel 會退回至以目標命名的合成單一案例報告，而 Tuist 會顯示每個目標的單一資料列（在測試案例清單中標示為 **Bazel 目標**），原始 `test.log` 仍可在執行頁面上取得。

大多數 Bazel 測試規則已產生真正的 `test.xml`：

- `java_test` 和 `kt_jvm_test`：內建 JUnit。
- 搭配 GoogleTest 的 `cc_test`：當針對較新的 gtest 編譯時，執行器會寫入 JUnit；較舊的設定需要 `--gtest_output=xml:$XML_OUTPUT_FILE`。
- `py_test`：使用帶有 `--junitxml=$XML_OUTPUT_FILE` 的 pytest，或 `rules_python` pytest 執行器。
- `go_test`：將 `go test -json` 導管至 `gotestsum --junitfile=$XML_OUTPUT_FILE`，或使用發出 JUnit 的輔助工具包裝。

來自 `rules_rust` 和 `rules_rs` 的 `rust_test` 會執行標準 `libtest` 測試框架，該框架在穩定版 Rust 上不會寫入 JUnit。請使用腳本包裝測試目標，以剖析 `libtest` 輸出並將 JUnit 寫入 `$XML_OUTPUT_FILE`；這樣你可以在 Tuist 中保留每個案例的資料列，而同一次執行仍維持為單一的 Bazel 測試目標。

## 測試身分識別 {#test-identity}

案例由目標標籤、類別名稱（若無則退回至套件名稱）和測試名稱識別。這可讓不同類別中同名方法保持獨立。使用不同外部套件名稱的舊報告會在其舊身分識別下保留歷史記錄；套用於舊身分識別的狀態變更需要重新套用到新身分識別，且當失敗符合舊身分識別時，命令會發出警告，讓你知道要移動哪項政策。

## 提供 CI 上下文 {#providing-ci-context}

Tuist 會從 Bazel 的建構中繼資料讀取 git 提交和分支資訊，以便比較不同環境中相同提交的執行結果。大多數持續整合系統已設定這些資訊；如果你的系統沒有，請明確傳遞：

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

相同的 `--build_metadata` 標記正是 <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel 建構洞察</.localized_link> 頁面所述用於標記呼叫的方式，因此一組標記即可涵蓋兩個介面。

## 不穩定測試與隔離 {#flaky-tests-and-quarantine}

重試、跨執行不穩定偵測以及每個案例的隔離（靜音和略過）都可透過 `tuist bazel test` 運作。請參閱 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel 不穩定測試</.localized_link> 以了解完整工作流程。

## 資料保留 {#data-retention}

Tuist 會保留產生測試執行的 Bazel 呼叫、其日誌以及待處理的測試攝取記錄 90 天。測試案例及其執行歷史記錄使用與其他建構系統相同的模型，不受該時間範圍限制。請參閱 <.localized_link href="/guides/server/data-retention">資料保留</.localized_link> 以了解完整政策。
