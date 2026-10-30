---
{
  "title": "Elixir Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and manage flaky tests in Elixir projects built with Mix."
}
---
# Elixir 不穩定測試 {#elixir-flaky-tests}

不穩定測試是指在多次使用相同程式碼執行時會產生不同結果（通過或失敗）的測試。它們會削弱對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助您隨時間追蹤它們。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共享 Elixir 設定</.localized_link> 以回報您的測試執行

![Phoenix 應用程式的不穩定測試](/images/guides/features/elixir/flaky-tests.png)

## 不穩定偵測運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

ExUnit 會執行每個測試一次，因此間歇性失敗的測試看起來與損壞的測試相同。啟用重試後，Hex 套件會再次執行失敗的測試，最多執行您設定的次數。在重試中通過的測試會被標記為不穩定，如果所有失敗的測試最終都通過，則該次執行視為成功。

預設情況下重試是關閉的。將 `test_retries` 新增至 `mix.exs` 中現有的 Tuist 選項以啟用它：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

或者針對單次執行，使用旗標或環境變數：

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

旗標優先於環境變數，而環境變數優先於 `mix.exs`。

只有失敗的測試會再次執行，就像 `mix test --failed` 執行它們的方式一樣，儀表板會顯示每次測試嘗試及其耗時。因 `--max-failures` 而提前停止的 ExUnit 執行不會重試。如果失敗的測試全部超時，該次執行也不會重試，因為每次重試都會再次等待所有超時。使用 `--warnings-as-errors` 時也會跳過重試，`mix test` 將不再強制執行此行為，且在 umbrella 專案的根目錄下也會跳過；請在其中一個應用程式內執行測試以進行重試。

![不穩定的 ExUnit 測試及其歷史記錄](/images/guides/features/elixir/flaky-test-case.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也可以透過比較同一提交在不同 CI 執行中的結果來偵測不穩定測試。如果一個測試在一次 CI 執行中通過，但在同一提交的另一次執行中失敗，則兩次執行都會被標記為不穩定。

這對於捕捉那些未能一致失敗以致無法被重試捕捉，但仍會導致間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測和清除透過專案上的 **自動化警示** 執行。每個專案都會獲得一個預設的「不穩定測試偵測」自動化，其 *觸發條件* 會將測試標記為不穩定，而其 *恢復機制* 會在測試經過設定的恢復視窗（預設 **14 天**）且未重新觸發後清除標記。在 **設定 → 自動化** 下編輯它以更改恢復視窗或完全停用恢復，以便測試保持標記為不穩定，直到您手動清除它們。

### 手動管理

您也可以從測試案例詳細資訊頁面手動標記或取消標記測試為不穩定。這在以下情況很有用：
- 您希望在修復已知不穩定測試的同時予以確認
- 測試因基礎設施問題而被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離可以防止不穩定測試在您修復時阻塞 CI。在儀表板的測試頁面上，將其狀態更改為 **靜音** 或 **跳過**，或在 **設定 → 自動化** 下設定自動化，當測試變為不穩定時將其靜音或跳過，並在恢復後再次啟用。在執行測試之前，`mix test` 會讀取專案的所有隔離測試並套用它們：

- **靜音**：測試會執行，其失敗仍會被報告，但如果執行的唯一失敗是靜音測試，則該次執行視為通過。重試仍會重新執行失敗的靜音測試，因此不穩定的測試可能會通過並被報告為不穩定。
- **跳過**：測試不會執行。`mix test` 會在執行開始前列出跳過的測試。

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

當任何非靜音的測試失敗，或因 `--max-failures` 而提前停止 ExUnit 時，執行會像往常一樣失敗。

> [!WARNING]
> **限制**
>
> - 只有最新版本的 Hex 套件會套用隔離。較早的版本會像其他測試一樣執行靜音和跳過的測試，因此靜音測試的失敗仍會導致執行失敗。在依賴它之前更新 `tuist_ex`。
> - 使用 `--warnings-as-errors` 或從 umbrella 專案的根目錄執行時，不會套用靜音測試。它們的失敗隨後會導致執行失敗。請改為在 umbrella 的每個應用程式內執行測試。
> - 跳過是根據測試的描述區塊和名稱進行匹配，而不是其模組。另一個模組中具有相同描述區塊和名稱的測試也會被跳過。請參閱 [跳過如何選擇測試](#how-skipping-selects-tests)。
> - 當您使用 `--only`、`--include` 或 `path:line` 選擇測試，或當測試未使用 `test` 宣告（例如 StreamData `property`）時，跳過的測試仍會執行。
> - 如果 `mix test` 無法讀取隔離的測試，它會執行每個測試並計算每次失敗。
> - 讀取隔離的測試需要憑證，即使是公開專案也是如此。沒有 `TUIST_TOKEN`、`mix tuist.login` 工作階段或持續整合身分識別權杖的執行不會套用隔離。這包括來自分叉的拉取請求，它們通常在沒有機密的情況下執行。
> - 使用 `--cover` 時，跳過的測試計為已移除：僅由它涵蓋的行會被報告為未涵蓋。
>
> `mix test` 會在摘要之後列出因跳過而錯誤遺漏的測試，以及仍然執行的跳過測試。

### 跳過如何選擇測試 {#how-skipping-selects-tests}

跳過的測試會透過基於其完整名稱的 ExUnit 過濾器排除，例如 `--exclude "test:test create_order/2 times out"`。ExUnit 過濾器也無法匹配模組，因此：

- 另一個模組中具有相同描述區塊和名稱的測試也會被排除。`mix test` 會在執行後列出這些測試。
- 當您使用 `--only`、`--include` 或 `path:line` 選擇測試時，即使該測試被跳過，它仍會執行，因為 ExUnit 會在排除過濾器之後套用包含過濾器。未使用 `test` 宣告的測試（例如 StreamData `property`）也是如此。`mix test` 會在執行後列出這些測試。

### 再次執行隔離的測試 {#running-quarantined-tests-again}

傳遞 `--no-quarantine` 以執行每個測試並計算每次失敗，例如用於檢查修復：

```bash
mix test --no-quarantine
```

在測試頁面上將其狀態恢復為 **已啟用**，以便在後續執行中包含它。跳過的測試在再次執行之前不會產生新結果。

如果 `mix test` 無法讀取隔離的測試，它會列印警告並執行所有測試而不套用隔離。若沒有憑證或已設定的專案，它會執行所有測試且不顯示警告。

Hex 套件尚未對新測試進行壓力測試。

## Slack 通知 {#slack-notifications}

透過在 Slack 整合中設定<.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</.localized_link>，在測試變得不穩定時立即收到通知。

## 查詢不穩定狀態 {#querying}

資料可透過 HTTP 取得。請參閱 API 參考文件中的 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以獲取完整的路由、過濾器和回應欄位清單。若要將測試案例標記為或不標記為不穩定，請傳送帶有 `is_flaky` 的 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`，或使用 `update_test_case` Model Context Protocol 工具。
