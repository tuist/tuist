---
{
  "title": "Elixir 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "偵測及管理以 Mix 建構嘅 Elixir 專案中嘅不穩定測試。"
}
---
# Elixir 不穩定測試 {#elixir-flaky-tests}

> [!IMPORTANT]
> **要求**
>
> - 完成<.localized_link href="/guides/get-started/elixir-project">共用 Elixir 設定</.localized_link>以回報你的測試執行

<!-- @snippet: ./_intro -->

![Phoenix 應用程式的不穩定測試](/images/guides/features/elixir/flaky-tests.png)

## 不穩定偵測如何運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

ExUnit 會執行每個測試一次，因此間歇性失敗的測試看起來與損壞的測試相同。啟用重試後，Hex 套件會再次執行失敗的測試，最多執行你設定的次數。在重試中通過的測試會被標記為不穩定，而如果所有失敗的測試最終都通過，則該次執行會成功。

預設情況下重試功能已關閉。將 `test_retries` 加入你在 `mix.exs` 中的現有 Tuist 選項以啟用它們：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

或者針對單次執行，使用旗標或環境變數：

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

旗標優先於環境變數，而環境變數優先於 `mix.exs`。

只有失敗的測試會再次執行，就像 `mix test --failed` 執行它們的方式一樣，而儀表板會顯示每次測試嘗試及其耗時。如果 ExUnit 因為 `--max-failures` 而提前停止執行，則不會重試。如果失敗的測試全部超時，也不會重試，因為每次重試都會再次等待所有超時。使用 `--warnings-as-errors` 時也會跳過重試，此時 `mix test` 不再強制執行，並且從 umbrella 專案的根目錄執行時也會跳過；請在其中一個應用程式內執行測試以進行重試。

![不穩定的 ExUnit 測試及其歷史記錄](/images/guides/features/elixir/flaky-test-case.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也可以透過比較同一提交在不同 CI 執行中的結果來偵測不穩定測試。如果測試在一次 CI 執行中通過，但在同一提交和方案標籤（`--scheme`）的另一次執行中失敗，則該失敗的執行會被標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試捕捉，但仍會導致間歇性 CI 失敗的不穩定測試特別有用。

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

隔離可以防止不穩定測試在你修復時阻塞 CI。在儀表板的測試頁面上，將其狀態更改為 **靜音** 或 **跳過**，或在 **設定 → 自動化** 下設定自動化，當測試變為不穩定時將其靜音或跳過，並在恢復後再次啟用。在執行測試之前，`mix test` 會讀取專案中每個被隔離的測試並應用它們：

- **靜音**：測試會執行，其失敗仍會被報告，但如果執行中唯一的失敗是靜音測試，則該次執行會通過。重試仍會重新執行失敗的靜音測試，因此不穩定的測試可能會通過並被報告為不穩定。
- **跳過**：測試不會執行。`mix test` 會在執行開始前列出跳過的測試。

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

如果任何非靜音的測試失敗，或者 ExUnit 因為 `--max-failures` 而提前停止，則執行會像往常一樣失敗。

> [!WARNING]
> **限制**
>
> - 只有最新版本的 Hex 套件會應用隔離。較早的版本會像其他測試一樣執行靜音和跳過的測試，因此靜音測試的失敗仍會導致執行失敗。在依賴它之前更新 `tuist_ex`。
> - 使用 `--warnings-as-errors` 或從 umbrella 專案的根目錄執行時，不會應用靜音測試。它們的失敗會導致執行失敗。請改為在 umbrella 的每個應用程式內執行測試。
> - 跳過是根據測試的描述區塊和名稱來匹配，而不是其模組。另一個模組中具有相同描述區塊和名稱的測試也會被跳過。請參閱 [跳過如何選擇測試](#how-skipping-selects-tests)。
> - 當你使用 `--only`、`--include` 或 `path:line` 選擇跳過的測試時，它仍會執行；或者當它不是用 `test` 宣告時，例如 StreamData `property`，它也會執行。
> - 如果 `mix test` 無法讀取被隔離的測試，它會執行每個測試並計算每次失敗。
> - 讀取被隔離的測試需要憑證，即使是公開專案也是如此。如果執行時沒有 `TUIST_TOKEN`、`mix tuist.login` 工作階段或持續整合身分令牌，則不會應用任何隔離。這包括來自分叉的拉取請求，它們通常在沒有密鑰的情況下運行。
> - 使用 `--cover` 時，跳過的測試計為已移除：僅由它覆蓋的行會被報告為未覆蓋。
>
> `mix test` 會在摘要之後列出因跳過而錯誤遺漏的測試，以及仍然執行的跳過測試。

### 跳過如何選擇測試 {#how-skipping-selects-tests}

跳過的測試會透過在其完整名稱上應用 ExUnit 過濾器而被排除，例如 `--exclude "test:test create_order/2 times out"`。ExUnit 過濾器無法同時匹配模組，因此：

- 另一個模組中具有相同描述區塊和名稱的測試也會被排除。`mix test` 會在執行後列出這些測試。
- 你使用 `--only`、`--include` 或 `path:line` 選擇的測試即使被跳過也會執行，因為 ExUnit 會在排除過濾器之後應用包含過濾器。不是用 `test` 宣告的測試也是如此，例如 StreamData `property`。`mix test` 會在執行後列出這些測試。

### 再次執行被隔離的測試 {#running-quarantined-tests-again}

傳遞 `--no-quarantine` 以執行每個測試並計算每次失敗，例如檢查修復：

```bash
mix test --no-quarantine
```

在其頁面上將測試返回 **啟用** 狀態，以便在後續執行中包含它。跳過的測試在再次執行之前不會產生新結果。

如果 `mix test` 無法讀取被隔離的測試，它會列印警告並執行每個測試而不應用隔離。如果沒有憑證或已設定的專案，它會執行每個測試而不發出警告。

Hex 套件尚未對新測試進行壓力測試。

<!-- @snippet: ./_slack -->

## 查詢不穩定狀態 {#querying}

數據可透過 HTTP 取得。請參閱 API 參考文件中的[測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以獲取完整的路由、過濾器和回應欄位清單。若要將測試案例標記為不穩定或取消標記，請傳送帶有 `is_flaky` 的 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`，或使用 `update_test_case` Model Context Protocol 工具。
