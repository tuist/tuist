---
{
  "title": "Elixir Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and manage flaky tests in Elixir projects built with Mix."
}
---
# Elixir 不穩定測試 {#elixir-flaky-tests}

不穩定測試是指使用相同程式碼多次執行時會產生不同結果（通過或失敗）的測試。它們會削弱你對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助你追蹤其隨時間的變化。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共享 Elixir 設定</.localized_link> 以報告你的測試執行

![Phoenix 應用程式的不穩定測試](/images/guides/features/elixir/flaky-tests.png)

## 不穩定偵測如何運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

ExUnit 只會執行每個測試一次，因此間歇性失敗的測試看起來與已損壞的測試相同。啟用重試後，Hex 套件會再次執行失敗的測試，最多執行你設定的次數。如果在重試中通過，該測試會被標記為不穩定，且如果所有失敗的測試最終都通過，則執行成功。

預設情況下重試是關閉的。將 `test_retries` 加入你在 `mix.exs` 中現有的 Tuist 選項以啟用它們：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

或者對於單次執行，使用標誌或環境變數：

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

標誌優先於環境變數，而環境變數優先於 `mix.exs`。

只有失敗的測試會再次執行，就像 `mix test --failed` 執行它們的方式一樣，並且儀表板會顯示每次測試嘗試及其耗時。如果 ExUnit 因為 `--max-failures` 而提前停止執行，則不會重試。如果失敗的測試全部超時，也不會重試，因為每次重試都會再次等待所有超時。使用 `--warnings-as-errors` 時也會跳過重試，這意味著 `mix test` 不再強制執行，並且在 umbrella 專案的根目錄下；請在其中的某個應用程式內執行測試以進行重試。

![不穩定的 ExUnit 測試及其歷史記錄](/images/guides/features/elixir/flaky-test-case.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也可以透過比較同一提交的不同 CI 執行結果來偵測不穩定測試。如果一個測試在一次 CI 執行中通過，但在同一提交的另一次執行中失敗，則兩次執行都會被標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試捕捉、但仍會導致間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測和清除透過專案上的 **自動化警報** 運行。每個專案都會獲得一個預設的「不穩定測試偵測」自動化，其 *觸發器* 會將測試標記為不穩定，而其 *恢復* 會在測試經過設定的恢復視窗（預設 **14 天**）且未重新觸發後清除標記。在 **設定 → 自動化** 下編輯它以更改恢復視窗或完全禁用恢復，以便測試保持標記為不穩定，直到你手動清除它們。

### 手動管理

你也可以從測試案例詳細頁面手動將測試標記為不穩定或取消標記。這在以下情況很有用：
- 你想在修復已知不穩定測試時確認它
- 由於基礎設施問題錯誤地標記了測試

## 隔離不穩定測試 {#quarantining}

隔離可以防止不穩定測試在你修復時阻塞 CI。在儀表板的測試頁面上，將其狀態更改為 **靜音** 或 **跳過**，或在 **設定 → 自動化** 下設定自動化，當測試變為不穩定時將其靜音或跳過，並在恢復後再次啟用。在執行測試之前，`mix test` 會讀取專案中每個被隔離的測試並應用它們：

- **靜音**：測試會執行，其失敗仍會被報告，但如果執行的唯一失敗是靜音測試，則執行通過。重試仍會重新執行失敗的靜音測試，因此不穩定的測試可能會通過並被報告為不穩定。
- **跳過**：測試不會執行。`mix test` 會在執行開始前列出跳過的測試。

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

如果任何非靜音測試失敗，或者 ExUnit 因為 `--max-failures` 而提前停止，則執行會像往常一樣失敗。

> [!WARNING]
> **限制**
>
> - 只有最新版本的 Hex 套件才會應用隔離。較早的版本會像其他測試一樣執行靜音和跳過的測試，因此靜音測試的失敗仍會導致執行失敗。在依賴它之前更新 `tuist_ex`。
> - 靜音測試不適用於 `--warnings-as-errors`，也不適用於 umbrella 專案的根目錄。它們的失敗會導致執行失敗。請改為在 umbrella 的每個應用程式內執行測試。
> - 跳過是根據測試的描述塊和名稱來匹配的，而不是其模組。另一個模組中具有相同描述塊和名稱的測試也會被跳過。請參閱 [跳過如何選擇測試](#how-skipping-selects-tests)。
> - 當你使用 `--only`、`--include` 或 `path:line` 選擇跳過的測試時，或者當它不是用 `test` 聲明時（例如 StreamData `property`），它仍然會執行。
> - 如果 `mix test` 無法讀取被隔離的測試，它會執行每個測試並計算每次失敗。
> - 讀取被隔離的測試需要憑證，即使是公開專案也是如此。沒有 `TUIST_TOKEN`、`mix tuist.login` 會話或持續整合身份令牌的情況下，不會應用任何隔離。這包括來自分叉的拉取請求，它們通常在沒有密鑰的情況下運行。
> - 使用 `--cover` 時，跳過的測試計為已移除：僅由它覆蓋的行會被報告為未覆蓋。
>
> `mix test` 會在摘要之後列出因錯誤而被跳過遺漏的測試，以及无论如何都執行的跳過測試。

### 跳過如何選擇測試 {#how-skipping-selects-tests}

跳過的測試會透過 ExUnit 過濾器以其全名排除，例如 `--exclude "test:test create_order/2 times out"`。ExUnit 過濾器無法同時匹配模組，因此：

- 另一個模組中具有相同描述塊和名稱的測試也會被排除。`mix test` 會在執行後命名這些測試。
- 當你使用 `--only`、`--include` 或 `path:line` 選擇測試時，即使該測試被跳過，它仍會執行，因為 ExUnit 會在排除過濾器之後應用包含過濾器。不是用 `test` 聲明的測試（例如 StreamData `property`）也是如此。`mix test` 會在執行後列出這些測試。

### 再次執行被隔離的測試 {#running-quarantined-tests-again}

傳遞 `--no-quarantine` 以執行每個測試並計算每次失敗，例如用於檢查修復：

```bash
mix test --no-quarantine
```

在測試頁面將其狀態改回 **已啟用**，以便在後續執行中包含它。被跳過的測試在再次執行之前不會產生新結果。

如果 `mix test` 無法讀取被隔離的測試，它會列印警告並執行所有測試（不包括被隔離的測試）。如果沒有憑證或未設定專案，它會執行所有測試且不會發出警告。

Hex 套件尚未對新測試進行壓力測試。

## Slack 通知 {#slack-notifications}

透過在 Slack 整合中設定<.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</.localized_link>，即可在測試變得不穩定時立即收到通知。

## 查詢不穩定狀態 {#querying}

資料可透過 HTTP 取得。請參閱 API 參考中的 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以獲取完整的路由、過濾器和回應欄位清單。若要將測試案例標記為或不標記為不穩定，請發送帶有 `is_flaky` 的 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`，或使用 `update_test_case` Model Context Protocol 工具。
