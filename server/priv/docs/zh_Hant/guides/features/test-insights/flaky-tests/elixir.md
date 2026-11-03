---
{
  "title": "Elixir 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "偵測並管理使用 Mix 建置的 Elixir 專案中的不穩定測試。"
}
---
# Elixir 不穩定測試 {#elixir-flaky-tests}

不穩定測試是指在相同程式碼下多次執行時，會產生不同結果（通過或失敗）的測試。這類測試會侵蝕你對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助你長期追蹤。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共用的 Elixir 設定</.localized_link> 以回報你的測試執行

![Phoenix 應用程式的不穩定測試](/images/guides/features/elixir/flaky-tests.png)

## 不穩定偵測如何運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

ExUnit 只會執行每個測試一次，因此間歇性失敗的測試看起來與損壞的測試無異。啟用重試後，Hex 套件會重新執行失敗的測試，最多執行你設定的次數。若在重試中通過，該測試會被標記為不穩定；只要所有失敗的測試最終都通過，該次執行就會成功。

預設關閉重試。在 `mix.exs` 中將 `test_retries` 加入現有的 Tuist 選項以啟用：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

或針對單次執行，使用旗標或環境變數：

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

旗標優先於環境變數，環境變數優先於 `mix.exs`。

只有失敗的測試會再次執行，就像 `mix test --failed` 執行它們的方式，且儀表板會顯示每次嘗試及其耗時。若 ExUnit 因 `--max-failures` 而提前停止執行，則不會重試。若失敗的測試全部逾時，也不會重試，因為每次重試都會再次等待所有逾時。使用 `--warnings-as-errors` 時也會略過重試，此時 `mix test` 不再強制執行；從 umbrella 專案的根目錄執行時也會略過重試；請在其中的某個應用程式內執行測試以進行重試。

![不穩定的 ExUnit 測試及其歷史記錄](/images/guides/features/elixir/flaky-test-case.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也能透過比較同一提交在不同 CI 執行中的結果來偵測不穩定測試。若某個測試在一次 CI 執行中通過，但在同一提交的另一次執行中失敗，這兩次執行都會被標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試機制抓到、但仍會導致間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測與清除會透過專案上的 **自動化警示** 執行。每個專案都會獲得一個預設的「不穩定測試偵測」自動化，其 *觸發條件* 會將測試標記為不穩定，而其 *恢復條件* 會在測試經過設定的恢復視窗（預設 **14 天**）且未再次觸發後清除標記。在 **設定 → 自動化** 中編輯它以變更恢復視窗，或完全停用恢復，讓測試保持標記為不穩定，直到你手動清除為止。

### 手動管理

你也可以從測試案例詳情頁面手動將測試標記或取消標記為不穩定。適用於以下情況：
- 你想在修復已知不穩定測試的同時承認其狀態
- 測試因基礎設施問題而被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離可防止不穩定測試在你修復期間阻擋 CI。在儀表板的測試頁面中，將其狀態改為 **靜音** 或 **略過**，或在 **設定 → 自動化** 中設定自動化，當測試變為不穩定時將其靜音或略過，並在恢復後再次啟用。在執行測試前，`mix test` 會讀取專案中每個被隔離的測試並套用：

- **靜音**：測試仍會執行且其失敗仍會被回報，但若執行中唯一的失敗來自靜音測試，該執行仍算通過。重試仍會重新執行失敗的靜音測試，因此不穩定測試可能通過並被標記為不穩定。
- **略過**：測試不會執行。`mix test` 會在執行開始前列出被略過的測試。

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

當任何非靜音的測試失敗，或 ExUnit 因 `--max-failures` 而提前停止時，執行會像往常一樣失敗。

> [!WARNING]
> **限制**
>
> - 只有較新版本的 Hex 套件會套用隔離。較舊版本會像其他測試一樣執行靜音和略過的測試，因此靜音測試的失敗仍會導致執行失敗。在依賴此功能前，請更新 `tuist_ex`。
> - 使用 `--warnings-as-errors` 或從 umbrella 專案的根目錄執行時，不會套用靜音測試。此時這些測試的失敗會導致執行失敗。請改為在 umbrella 中的每個應用程式內執行測試。
> - 略過是依據測試的 describe 區塊與名稱來比對，而非模組。另一個模組中具有相同 describe 區塊與名稱的測試也會被略過。請參閱 [略過如何選取測試](#how-skipping-selects-tests)。
> - 當你使用 `--only`、`--include` 或 `path:line` 選取測試，或測試並非以 `test` 宣告（例如 StreamData 的 `property`）時，被略過的測試仍會執行。
> - 若 `mix test` 無法讀取被隔離的測試，它會執行所有測試並計算每次失敗。
> - 讀取被隔離的測試需要憑證，即使是公開專案也是如此。若執行時缺少 `TUIST_TOKEN`、`mix tuist.login` 工作階段或持續整合身分令牌，則不會套用任何隔離。這包括來自分叉的拉取請求，它們通常在沒有密鑰的情況下執行。
> - 使用 `--cover` 時，被略過的測試視為已移除：僅由該測試涵蓋的行會被回報為未涵蓋。
>
> `mix test` 會在摘要之後列出因略過而被遺漏的測試，以及仍被執行的略過測試。

### 略過如何選取測試 {#how-skipping-selects-tests}

被略過的測試會透過 ExUnit 過濾器以其完整名稱排除，例如 `--exclude "test:test create_order/2 times out"`。ExUnit 過濾器無法同時比對模組，因此：

- 另一個模組中具有相同 describe 區塊與名稱的測試也會被排除。`mix test` 會在執行後列出這些測試。
- 當你使用 `--only`、`--include` 或 `path:line` 選取測試時，即使該測試被略過仍會執行，因為 ExUnit 會在排除過濾器之後套用包含過濾器。並非以 `test` 宣告的測試（例如 StreamData 的 `property`）也是如此。`mix test` 會在執行後列出這些測試。

### 再次執行被隔離的測試 {#running-quarantined-tests-again}

傳入 `--no-quarantine` 以執行所有測試並計算每次失敗，例如用於驗證修復：

```bash
mix test --no-quarantine
```

在測試頁面將其狀態改回 **已啟用**，以便在後續執行中包含它。被略過的測試在再次執行之前不會產生新結果。

若 `mix test` 無法讀取被隔離的測試，它會列印警告並執行所有測試（不含隔離設定）。若缺少憑證或未設定專案，它會執行所有測試且不顯示警告。

Hex 套件尚未對新測試進行壓力測試。

## Slack 通知 {#slack-notifications}

透過在 Slack 整合中設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</.localized_link>，在測試變得不穩定時立即收到通知。

## 查詢不穩定狀態 {#querying}

資料可透過 HTTP 取得。請參閱 API 參考文件中的 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以查看完整的路由、過濾器和回應欄位清單。若要將測試案例標記為或不標記為不穩定，請傳送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` 並附上 `is_flaky`，或使用 `update_test_case` Model Context Protocol 工具。
