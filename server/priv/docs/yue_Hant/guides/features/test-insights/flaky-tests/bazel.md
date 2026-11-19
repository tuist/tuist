---
{
  "title": "Bazel 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "偵測 Bazel 嘅不穩定測試，將失敗靜音，並跳過已隔離嘅目標。"
}
---
# Bazel 不穩定測試 {#bazel-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 透過 `tuist bazel setup` 設定 <.localized_link href="/guides/features/test-insights/bazel">Bazel 測試洞察</.localized_link>。

<!-- @snippet: ./_intro -->

## 不穩定偵測運作方式 {#how-it-works}

Tuist 會使用 Bazel `test.xml` 報告中的個別測試案例，以偵測在重試之間，以及在持續整合中相同提交與目標選擇的不同執行之間的不一致結果。本機執行仍會顯示，但不會自動將測試案例標記為不穩定。

### 測試重試 {#test-retries}

重試為選用項目，且與隔離無關。`--flaky_test_attempts=3` 會啟用每個測試最多 **三次 Bazel 總嘗試次數**，而非額外三次重試。請將現有的重試設定保留在 `.bazelrc`，或明確傳遞：

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

必須實際執行重試，Tuist 才能觀察其結果。僅憑 Bazel 目標的不穩定摘要，無法識別哪個個別案例不穩定。

### 跨執行偵測 {#cross-run-detection}

比較執行需要提交與分支的中繼資料。當你的建置環境未自動發布這些資料時，請提供：

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

案例會根據目標標籤、類別名稱（若無則退回至套件名稱）以及測試名稱來識別，詳情請參閱 <.localized_link href="/guides/features/test-insights/bazel">Bazel 測試洞察</.localized_link>。

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test` 會在每次叫用前擷取隔離政策，並將其套用至底層的 `bazel test` 執行。一般的 `bazel test` 仍會回報測試結果，但不會套用隔離：

```sh
tuist bazel test -- //app:tests
```

`--` 之後的引數會轉發至 `bazel test`。使用 `--path` 來選擇專案與工作目錄，並使用 `--bazel` 來選擇不同的可執行檔（例如 `bazelisk`）。命名的 Bazel 設定（例如 `--config=ci`）為選用項目，運作方式相同。

### 靜音 {#mute}

使用 **靜音** 作為主要的隔離工作流程。被靜音的案例仍會繼續執行，其失敗仍然可見，而健康的同層案例仍會影響結果。只有當報告將每個失敗目標中的所有失敗都歸因於被靜音的案例時，Tuist 才會將 Bazel 的測試失敗結束狀態改為成功。建置錯誤、逾時、中斷的執行、遺失或不完整的報告，以及不在靜音集合內的失敗，都會保留 Bazel 的失敗狀態。

### 略過 {#skip}

略過是以 Bazel 目標為單位：略過一個案例會排除其整個目標（包括健康的案例），因為 Bazel 無法為每個測試框架過濾個別案例。除非你打算排除整個目標，否則請優先使用 **靜音**。指令會列印每個被排除的目標標籤，讓建置記錄顯示隔離政策排除了哪些內容。

如果被略過的目標已不存在，Tuist 會在警告中指明該目標，並在沒有該排除的情況下執行。將過時的案例恢復為 **已啟用**，以永久移除其政策。如果沒有剩餘的測試目標，Bazel 會維持其正常的「找不到測試」結束狀態。

<!-- @snippet: ./_quarantined-passing -->

### 再次執行已隔離的測試 {#running-quarantined-tests-again}

若要調查或驗證修復，請繞過隔離政策：

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

將案例恢復為 **已啟用**，以便在後續的正常執行中包含其目標。被略過的案例在明確包含之前不會產生新的執行，因此基於成功新執行的自動化流程需要先進行驗證執行，才能恢復它們。

### 限制 {#limitations}

- 明確的 `--build_event_json_file` 或 `--target_pattern_file` 無法與作用中的隔離同時使用。請直接傳遞目標模式。
- 如果 Tuist 無法擷取隔離政策，指令會在執行測試前停止。它永遠不會套用部分政策。當你故意想要在不套用政策的情況下執行時，請使用 `--no-quarantine`。
- 符合以較舊的套件為基礎的身份記錄之靜音的失敗，仍會造成阻擋，而指令會指明要重新套用的政策。

請參閱 Bazel 的 [測試過濾器](https://bazel.build/docs/user-manual#test-filter)、[指令選項](https://bazel.build/reference/command-line-reference) 和 [建置事件描述](https://bazel.build/remote/bep-glossary)，以了解底層行為。

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
