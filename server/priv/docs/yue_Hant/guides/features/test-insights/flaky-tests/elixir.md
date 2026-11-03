---
{
  "title": "Elixir 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "偵測及管理以 Mix 構建的 Elixir 專案中的不穩定測試。"
}
---
# Elixir 不穩定測試 {#elixir-flaky-tests}

不穩定測試係指用同一份代碼多次運行時，會產生唔同結果（通過或失敗）嘅測試。佢哋會削弱你對測試套件嘅信任，亦浪費開發人員時間去調查誤報失敗。Tuist 會自動偵測不穩定測試，並幫你追蹤佢哋隨時間嘅變化。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共享 Elixir 設定</.localized_link> 以報告你嘅測試運行

![Phoenix 應用程式嘅不穩定測試](/images/guides/features/elixir/flaky-tests.png)

## 不穩定偵測如何運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

ExUnit 每次只運行每個測試一次，所以間歇性失敗嘅測試睇落同壞咗嘅測試一樣。啟用重試後，Hex 套件會重新運行失敗嘅測試，最多達到你設定嘅次數。如果測試喺重試時通過，就會被標記為不穩定；如果所有失敗嘅測試最終都通過，則該次運行視為成功。

重試預設係關閉嘅。喺 `mix.exs` 入面現有嘅 Tuist 選項中加入 `test_retries` 即可啟用：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

或者針對單次運行，使用標誌或環境變數：

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

標誌優先於環境變數，而環境變數優先於 `mix.exs`。

只有失敗嘅測試會重新運行，方式同 `mix test --failed` 運行佢哋一樣，儀表板會顯示每次測試嘗試及其耗時。如果 ExUnit 因為 `--max-failures` 而提前停止運行，則不會重試。如果一次運行中所有失敗嘅測試都超時，亦不會重試，因為每次重試都要重新等待所有超時。使用 `--warnings-as-errors` 時亦會跳過重試，此時 `mix test` 不再強制執行；另外，從 umbrella 專案根目錄運行時亦會跳過重試；請進入其中一個應用程式內部運行測試以進行重試。

![一個不穩定嘅 ExUnit 測試及其歷史記錄](/images/guides/features/elixir/flaky-test-case.png)

### 跨運行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 亦可以透過比較同一個 commit 上唔同 CI 運行嘅結果來偵測不穩定測試。如果一個測試喺某次 CI 運行中通過，但喺同一個 commit 嘅另一次運行中失敗，則兩次運行都會被標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試捕捉、但仍然導致間歇性 CI 失敗嘅不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測和清除透過專案上嘅 **自動化警報** 進行。每個專案都會獲得一個預設嘅「不穩定測試偵測」自動化，其 *觸發器* 會將測試標記為不穩定，而其 *恢復* 機制會在測試經過設定嘅恢復窗口（預設 **14 天**）且未再次觸發後清除標記。你可以喺 **設定 → 自動化** 下編輯它以更改恢復窗口，或完全禁用恢復，令測試保持標記為不穩定，直到你手動清除。

### 手動管理

你亦可以喺測試案例詳情頁面手動將測試標記為或不標記為不穩定。以下情況尤其有用：
- 你想喺修復已知不穩定測試期間確認其狀態
- 測試因基礎設施問題而被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離可以防止不穩定測試喺你修復期間阻塞 CI。喺儀表板嘅測試頁面，將其狀態更改為 **靜音** 或 **跳過**，或者喺 **設定 → 自動化** 下配置一個自動化，當測試變為不穩定時將其靜音或跳過，並在恢復後重新啟用。喺運行測試之前，`mix test` 會讀取專案中每個被隔離嘅測試並應用：

- **靜音**：測試會運行，其失敗仍會被報告，但如果一次運行中只有靜音測試失敗，則該次運行視為通過。重試仍然會重新運行失敗嘅靜音測試，因此不穩定測試可能通過並被報告為不穩定。
- **跳過**：測試不會運行。`mix test` 會喺運行開始前列出被跳過嘅測試。

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

當任何非靜音測試失敗，或 ExUnit 因為 `--max-failures` 而提前停止時，運行會像往常一樣失敗。

> [!WARNING]
> **限制**
>
> - 只有較新版本嘅 Hex 套件才會應用隔離。較舊版本會像其他測試一樣運行靜音和跳過嘅測試，因此靜音測試嘅失敗仍然會導致運行失敗。喺依賴此功能之前，請更新 `tuist_ex`。
> - 使用 `--warnings-as-errors` 或從 umbrella 專案根目錄運行時，不會應用靜音測試。此時佢哋嘅失敗會導致運行失敗。請改為喺 umbrella 中每個應用程式內部運行測試。
> - 跳過係根據測試嘅 describe 塊和名稱來匹配，而非模組。另一個模組中具有相同 describe 塊和名稱嘅測試亦會被跳過。請參閱 [跳過如何選擇測試](#how-skipping-selects-tests)。
> - 當你使用 `--only`、`--include` 或 `path:line` 選擇測試，或者測試並非使用 `test` 聲明（例如 StreamData `property`）時，被跳過嘅測試仍然會運行。
> - 如果 `mix test` 無法讀取被隔離嘅測試，它會運行每個測試並計算每次失敗。
> - 讀取被隔離嘅測試需要憑證，即使是公開專案亦然。如果運行時沒有 `TUIST_TOKEN`、`mix tuist.login` 會話或持續集成身份令牌，則不會應用任何隔離。這包括來自 fork 嘅拉取請求，它們通常喺沒有密鑰嘅情況下運行。
> - 使用 `--cover` 時，被跳過嘅測試會被視為移除：只有它覆蓋嘅行會被報告為未覆蓋。
>
> `mix test` 會喺總結之後列出因跳過而錯誤遺漏嘅測試，以及仍然運行嘅被跳過測試。

### 跳過如何選擇測試 {#how-skipping-selects-tests}

被跳過嘅測試會透過基於其完整名稱嘅 ExUnit 過濾器被排除，例如 `--exclude "test:test create_order/2 times out"`。ExUnit 過濾器無法同時匹配模組，因此：

- 另一個模組中具有相同 describe 塊和名稱嘅測試亦會被排除。`mix test` 會喺運行之後列出這些測試。
- 當你使用 `--only`、`--include` 或 `path:line` 選擇測試時，即使該測試被跳過，它仍然會運行，因為 ExUnit 會在排除過濾器之後應用包含過濾器。並非使用 `test` 聲明嘅測試（例如 StreamData `property`）亦會如此。`mix test` 會喺運行之後列出這些測試。

### 再次運行被隔離嘅測試 {#running-quarantined-tests-again}

傳遞 `--no-quarantine` 以運行每個測試並計算每次失敗，例如用於檢查修復：

```bash
mix test --no-quarantine
```

喺測試頁面將其狀態恢復為 **已啟用**，以便喺後續運行中包含它。被跳過嘅測試喺再次運行之前不會產生新結果。

如果 `mix test` 無法讀取被隔離嘅測試，它會打印警告並運行所有測試（不包括被隔離嘅測試）。如果沒有憑證或未配置專案，它會運行所有測試且不會顯示警告。

Hex 套件尚未對新測試進行壓力測試。

## Slack 通知 {#slack-notifications}

透過喺你嘅 Slack 整合中設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試提醒</.localized_link>，喺測試變得不穩定時立即收到通知。

## 查詢不穩定狀態 {#querying}

數據可透過 HTTP 獲取。請參閱 API 參考中嘅 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以獲取完整嘅路由、過濾器和響應字段列表。若要將測試案例標記為或不標記為不穩定，請發送帶有 `is_flaky` 嘅 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`，或使用 `update_test_case` Model Context Protocol 工具。
