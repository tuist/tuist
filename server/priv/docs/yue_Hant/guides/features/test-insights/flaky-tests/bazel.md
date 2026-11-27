---
{
  "title": "Bazel 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "偵測 Bazel 不穩定測試，將失敗設為靜音，並跳過隔離目標。"
}
---
# Bazel 不穩定測試 {#bazel-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 透過 `tuist bazel setup` 設定 <.localized_link href="/guides/features/test-insights/bazel">Bazel 測試洞察</.localized_link>。

<!-- @snippet: ./_intro -->

## 不穩定測試偵測運作方式 {#how-it-works}

Tuist 會使用 Bazel `test.xml` 報告中的個別測試案例，偵測在重試之間，以及在持續整合中相同提交與目標選擇的各次執行之間的不一致結果。本機執行仍會顯示，但不會自動將測試案例標記為不穩定。

### 測試重試 {#test-retries}

重試為選用項目，且與隔離無關。`--flaky_test_attempts=3` 可讓每個測試最多進行 **三次 Bazel 總嘗試次數**，而非額外重試三次。請將現有的重試設定保留在 `.bazelrc`，或明確傳入：

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

必須實際執行重試，Tuist 才能觀察其結果。單靠 Bazel 目標的不穩定摘要，無法識別哪個個別案例屬於不穩定。

### 跨執行偵測 {#cross-run-detection}

比較各次執行需要提交與分支的中繼資料。當你的建構環境未自動發布這些資料時，請自行提供：

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

案例會依據目標標籤、類別名稱（若無則退回使用套件名稱）及測試名稱來識別，詳情請參閱 <.localized_link href="/guides/features/test-insights/bazel">Bazel 測試洞察</.localized_link>。

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test` 會在每次呼叫前取得隔離政策，並將其套用至底層的 `bazel test` 執行。一般的 `bazel test` 仍會回報測試結果，但不會套用隔離：

```sh
tuist bazel test -- //app:tests
```

`--` 之後的引數會轉發給 `bazel test`。使用 `--path` 選取專案與工作目錄，並使用 `--bazel` 選取其他可執行檔（例如 `bazelisk`）。具名的 Bazel 設定（例如 `--config=ci`）為選用項目，運作方式相同。

### 靜音 {#mute}

將 **靜音** 作為主要的隔離工作流程。被靜音的案例仍會繼續執行，其失敗情況依然可見，而正常的同層案例仍會影響結果。只有當報告將每個失敗目標中的所有失敗都歸因於被靜音的案例時，Tuist 才會將 Bazel 的測試失敗退出狀態改為成功。建構錯誤、逾時、中斷的執行、遺失或不完整的報告，以及不在靜音集合內的失敗，都會保留 Bazel 的失敗狀態。

### 略過 {#skip}

略過以 Bazel 目標為單位運作：略過某個案例會排除其整個目標（包括正常的案例），因為 Bazel 無法針對每個測試框架過濾個別案例。除非你打算排除整個目標，否則建議優先使用 **靜音**。指令會列印每個被排除的目標標籤，讓建構記錄顯示隔離政策排除了哪些項目。

如果被略過的目標已不存在，Tuist 會在警告中指出該目標，並在不含該排除的情況下執行。將過時的案例回復為 **啟用**，以永久移除其政策。如果沒有剩餘的測試目標，Bazel 會維持其正常的「找不到測試」退出狀態。

<!-- @snippet: ./_quarantined-passing -->

### 再次執行已隔離的測試 {#running-quarantined-tests-again}

若要調查或驗證修復，可繞過隔離政策：

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

將案例回復為 **啟用**，以便在後續的正常執行中包含其目標。被略過的案例在明確包含之前不會產生新的執行，因此基於成功新執行的自動化流程需要先進行驗證執行，才能恢復它們。

### 限制 {#limitations}

- 明確的 `--build_event_json_file` 或 `--target_pattern_file` 不能與作用中的隔離同時使用。請直接傳遞目標模式。
- 如果 Tuist 無法取得隔離政策，指令會在執行測試前停止。它絕不會套用部分政策。當你刻意想要在不套用隔離的情況下執行時，請使用 `--no-quarantine`。
- 若某個失敗符合以較舊的套件基礎身分記錄的靜音規則，該失敗仍會阻擋執行，而指令會指出需要重新套用的政策。

如需了解底層行為，請參閱 Bazel 的 [測試過濾器](https://bazel.build/docs/user-manual#test-filter)、[指令選項](https://bazel.build/reference/command-line-reference) 及 [建構事件說明](https://bazel.build/remote/bep-glossary)。

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
