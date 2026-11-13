---
{
  "title": "Elixir 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "偵測並管理使用 Mix 建置的 Elixir 專案中的不穩定測試。"
}
---
# Elixir 不穩定測試 {#elixir-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/elixir-project">共用的 Elixir 設定</.localized_link>以回報你的測試執行

<!-- @snippet: ./_intro -->

![Phoenix 應用程式的不穩定測試](/images/guides/features/elixir/flaky-tests.png)

## 不穩定偵測的運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

ExUnit 會將每個測試執行一次，因此間歇性失敗的測試看起來與損壞的測試相同。啟用重試後，Hex 套件會重新執行失敗的測試，最多達到你設定的次數。若在重試中通過，該測試會被標記為不穩定；只要所有失敗的測試最終都通過，該次執行即視為成功。

預設關閉重試。在 `mix.exs` 中現有的 Tuist 選項加入 `test_retries` 即可啟用：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

或者針對單次執行，使用旗標或環境變數：

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

旗標優先於環境變數，環境變數優先於 `mix.exs`。

只有失敗的測試會再次執行，如同 `mix test --failed` 的執行方式；儀表板會顯示每次嘗試及其耗時。若 ExUnit 因 `--max-failures` 而提前停止執行，則不會重試。若所有失敗的測試皆逾時，也不會重試，因為每次重試都會再次等待所有逾時。使用 `--warnings-as-errors` 時也會略過重試，此時 `mix test` 不再強制執行；從 umbrella 專案的根目錄執行時也會略過重試，請在 umbrella 內的其中一個應用程式中執行測試以進行重試。

![不穩定的 ExUnit 測試及其歷史記錄](/images/guides/features/elixir/flaky-test-case.png)

### 跨執行偵測 {#cross-run-detection}

即使未啟用測試重試，Tuist 仍可透過比較同一提交在不同 CI 執行中的結果來偵測不穩定測試。若某個測試在一次 CI 執行中通過，但在同一提交與 scheme 標籤（`--scheme`）的另一次執行中失敗，該失敗的執行會被標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試機制發現、但仍會造成 CI 間歇性失敗的不穩定測試特別有用。

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

隔離可防止不穩定測試在你修復期間阻礙 CI。在儀表板的測試頁面中，將其狀態改為**靜音**或**略過**，或在**設定 → 自動化**下設定自動化規則，當測試變為不穩定時將其靜音或略過，並在恢復後重新啟用。在執行測試前，`mix test` 會讀取專案中所有已隔離的測試並套用：

- **靜音**：測試仍會執行並回報失敗，但若執行中唯一的失敗來自靜音測試，該次執行仍視為通過。重試仍會重新執行失敗的靜音測試，因此不穩定測試可能通過並被標記為不穩定。
- **略過**：測試不會執行。`mix test` 會在執行開始前列出略過的測試。

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

當任何非靜音的測試失敗，或 ExUnit 因 `--max-failures` 而提前停止時，執行會如常失敗。

> [!WARNING]
> **限制**
>
> - 只有較新版本的 Hex 套件會套用隔離。較早版本會像其他測試一樣執行靜音與略過的測試，因此靜音測試的失敗仍會導致執行失敗。在依賴此功能前，請更新 `tuist_ex`。
> - 使用 `--warnings-as-errors` 或從 umbrella 專案的根目錄執行時，不會套用靜音測試。此時這些測試的失敗會導致執行失敗。請改為在 umbrella 內的每個應用程式中執行測試。
> - 略過是依據測試的 describe 區塊與名稱進行比對，而非模組。若另一個模組中有相同的 describe 區塊與名稱，該測試也會被略過。請參閱[略過如何選取測試](#how-skipping-selects-tests)。
> - 當你使用 `--only`、`--include` 或 `path:line` 選取測試，或測試並非以 `test` 宣告（例如 StreamData 的 `property`）時，略過的測試仍會執行。
> - 若 `mix test` 無法讀取已隔離的測試，它會執行所有測試並計算所有失敗。
> - 讀取已隔離的測試需要憑證，即使是公開專案亦然。若執行時缺少 `TUIST_TOKEN`、`mix tuist.login` 工作階段或持續整合身分令牌，則不會套用任何隔離。這包含來自分叉的拉取請求，它們通常在不提供密鑰的情況下執行。
> - 使用 `--cover` 時，略過的測試會被視為移除：僅由該測試涵蓋的行會被回報為未涵蓋。
>
> `mix test` 會在摘要之後列出因略過而誤遺漏的測試，以及仍被執行的略過測試。

### 略過如何選取測試 {#how-skipping-selects-tests}

略過的測試會透過 ExUnit 以其完整名稱進行過濾而被排除，例如 `--exclude "test:test create_order/2 times out"`。ExUnit 過濾器無法同時比對模組，因此：

- 若另一個模組中有相同的 describe 區塊與名稱，該測試也會被排除。`mix test` 會在執行後列出這些測試。
- 當你使用 `--only`、`--include` 或 `path:line` 選取測試時，即使該測試已被略過仍會執行，因為 ExUnit 會在排除過濾器之後套用包含過濾器。並非以 `test` 宣告的測試（例如 StreamData 的 `property`）也是如此。`mix test` 會在執行後列出這些測試。

### 再次執行已隔離的測試 {#running-quarantined-tests-again}

傳遞 `--no-quarantine` 以執行所有測試並計算所有失敗，例如用於驗證修復：

```bash
mix test --no-quarantine
```

在測試頁面將其狀態改回**啟用**，以便在後續執行中包含它。略過的測試在再次執行前不會產生新結果。

若 `mix test` 無法讀取已隔離的測試，它會列印警告並執行所有測試（不套用隔離）。若缺少憑證或未設定專案，它會執行所有測試且不會列印警告。

Hex 套件尚未對新測試進行壓力測試。

<!-- @snippet: ./_slack -->

## 查詢不穩定狀態 {#querying}

資料可透過 HTTP 取得。請參閱 API 參考文件中的[測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以查看完整的路由、過濾器和回應欄位清單。若要將測試案例標記或取消標記為不穩定，請傳送帶有 `is_flaky` 的 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`，或使用 `update_test_case` Model Context Protocol 工具。
