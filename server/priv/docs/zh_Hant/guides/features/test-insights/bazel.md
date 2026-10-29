---
{
  "title": "Bazel Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Bazel test analytics in the Tuist dashboard to monitor test performance and reliability."
}
---
# Bazel 測試洞察 {#bazel-test-insights}

透過 Tuist 執行 Bazel 測試，將資料填入與其他建構系統相同的測試儀表板：

```bash
tuist bazel test -- //app:tests
```

`--` 之後的引數會轉發給 `bazel test`。使用 `--path` 來選擇專案與工作目錄，並使用 `--bazel` 來選擇不同的可執行檔，例如 `bazelisk`。一般的 `bazel test` 仍會回報測試結果，但不會取得或強制執行 Tuist 隔離政策。

> [!NOTE]
> `tuist bazel test` 包裝器僅在處理 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">隔離測試</.localized_link> 時需要。常規測試執行的個別案例回報是由 `tuist bazel setup` 在 `.bazelrc.tuist` 中設定，因此單純執行 `bazel test` 也會回報個別案例。

## 追蹤內容 {#what-is-tracked}

Tuist 會解析 `test.xml` 報告，並擷取 Bazel 為每個測試目標產生的 `test.log` 輸出，然後將其彙整至共用的測試執行模型。每次執行會記錄：

- 個別測試案例的通過、失敗與跳過狀態，以及持續時間。
- 測試目標、類別與套件結構。
- 當 Bazel 設定為重試不穩定測試時的重試嘗試。
- 從目標的 `test.log` 擷取的失敗輸出。

**測試執行**、**測試案例** 與個別測試頁面在 Bazel 上的運作方式，與其他建構系統相同。

## 產生個別案例的 JUnit 報告 {#per-case-junit-reports}

個別案例列取決於測試目標是否在 Bazel 提供的 `$XML_OUTPUT_FILE` 路徑寫入 JUnit `test.xml`。當執行器未寫入時，Bazel 會退回至以目標命名的合成單一案例報告，而 Tuist 會在「測試案例」清單中顯示每個目標一列（標示為 **Bazel 目標**），並在執行頁面保留原始的 `test.log` 供檢視。

大多數 Bazel 測試規則已能產生真正的 `test.xml`：

- `java_test` 與 `kt_jvm_test`：內建 JUnit 支援。
- 搭配 GoogleTest 的 `cc_test`：當針對較新的 gtest 編譯時，執行器會寫入 JUnit；較舊的設定需要 `--gtest_output=xml:$XML_OUTPUT_FILE`。
- `py_test`：使用 pytest 並加上 `--junitxml=$XML_OUTPUT_FILE`，或使用 `rules_python` pytest 執行器。
- `go_test`：將 `go test -json` 透過 `gotestsum --junitfile=$XML_OUTPUT_FILE` 管線處理，或以輔助工具包裝以產生 JUnit。

來自 `rules_rust` 與 `rules_rs` 的 `rust_test` 會執行標準的 `libtest` 測試框架，其在穩定版 Rust 上不會寫入 JUnit。請以腳本包裝測試目標，解析 `libtest` 輸出並將 JUnit 寫入 `$XML_OUTPUT_FILE`；這樣可在 Tuist 中保留個別案例列，且同一執行仍維持為單一 Bazel 測試目標。

## 測試識別 {#test-identity}

案例由目標標籤、類別名稱（若無則退回至套件名稱）與測試名稱來識別。這能讓不同類別中同名方法保持區隔。使用不同外層套件名稱的舊報告會以舊識別保留其歷史紀錄；套用於舊識別的狀態變更需要重新套用到新識別，且當失敗符合舊識別時，命令會發出警告，讓您知道應移動哪項政策。

## 提供 CI 上下文 {#providing-ci-context}

Tuist 會從 Bazel 的建構中繼資料讀取 Git 提交與分支資訊，以便比較不同環境中相同提交的執行。多數持續整合系統已設定這些資訊；若您的系統未設定，請明確傳入：

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

相同的 `--build_metadata` 旗標正是 <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel 建構洞察</.localized_link> 頁面所述用於標記呼叫的方式，因此一組旗標即可涵蓋兩個介面。

## 不穩定測試與隔離 {#flaky-tests-and-quarantine}

重試、跨執行不穩定偵測，以及個別案例隔離（靜音與跳過）皆可透過 `tuist bazel test` 運作。完整工作流程請參閱 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel 不穩定測試</.localized_link>。

## 資料保留 {#data-retention}

Tuist 會保留產生測試執行的 Bazel 呼叫、其日誌，以及待處理的測試攝取記錄，期限為 90 天。測試案例及其執行歷史使用與其他建構系統相同的模型，不受該時間窗限制。完整政策請參閱 <.localized_link href="/guides/server/data-retention">資料保留</.localized_link>。
