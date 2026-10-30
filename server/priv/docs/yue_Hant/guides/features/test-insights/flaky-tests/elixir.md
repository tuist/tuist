---
{
  "title": "Elixir 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "偵測及管理以 Mix 構建嘅 Elixir 專案中嘅不穩定測試。"
}
---
# Elixir 不穩定測試 {#elixir-flaky-tests}

不穩定測試係指用同一份代碼多次運行時，會產生唔同結果（通過或失敗）嘅測試。佢哋會削弱你對測試套件嘅信任，亦會浪費開發人員時間去調查虛假失敗。Tuist 會自動偵測不穩定測試，並幫你隨住時間追蹤佢哋。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共享 Elixir 設定</.localized_link> 以報告你嘅測試運行

![Phoenix 應用程式嘅不穩定測試](/images/guides/features/elixir/flaky-tests.png)

## 不穩定偵測點樣運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

ExUnit 每次只運行每個測試一次，所以間歇性失敗嘅測試睇落同壞咗嘅測試一樣。啟用重試後，Hex 套件會再次運行失敗嘅測試，最多達到你設定嘅次數。如果重試時通過，該測試會被標記為不穩定；如果所有失敗嘅測試最終都通過，則運行成功。

預設情況下重試係關閉嘅。將 `test_retries` 加入你喺 `mix.exs` 中現有嘅 Tuist 選項以启用佢哋：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

或者對於單次運行，使用標誌或環境變數：

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

標誌優先於環境變數，而環境變數優先於 `mix.exs`。

只有失敗嘅測試會再次運行，就像 `mix test --failed` 運行佢哋嘅方式一樣，儀表板會顯示每次測試嘗試及其耗時。如果 ExUnit 因為 `--max-failures` 而提前停止運行，則不會重試。如果運行中所有失敗嘅測試都超時，亦不會重試，因為每次重試都會再次等待所有超時。使用 `--warnings-as-errors` 時亦會跳過重試，此時 `mix test` 將不再強制執行；另外，從 umbrella 項目嘅根目錄運行時亦會跳過重試；請喺其中一個應用程式內部運行測試以進行重試。

![一個不穩定嘅 ExUnit 測試及其歷史記錄](/images/guides/features/elixir/flaky-test-case.png)

### 跨運行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 亦可以透過比較同一提交上唔同 CI 運行嘅結果來偵測不穩定測試。如果一個測試喺一次 CI 運行中通過，但在同一提交嘅另一次運行中失敗，則兩次運行都會被標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試捕捉、但仍會導致間歇性 CI 失敗嘅不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測和清除係透過項目上嘅 **自動化警報** 進行。每個項目都會獲得一個默認嘅「不穩定測試偵測」自動化，其 *觸發器* 會將測試標記為不穩定，而其 *恢復* 機制會在測試經過配置嘅恢復窗口（默認 **14 天**）且未重新觸發後清除該標記。你可以喺 **設定 → 自動化** 下編輯它以更改恢復窗口或完全禁用恢復，令測試保持標記為不穩定，直到你手動清除佢哋。

### 手動管理

你亦可以喺測試案例詳情頁面手動標記或取消標記測試為不穩定。這喺以下情況很有用：
- 你想喺修復已知不穩定測試時確認佢
- 測試因基礎設施問題而被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離可以防止不穩定測試喺你修復期間阻塞 CI。喺儀表板嘅測試頁面中，將其狀態更改為 **靜音** 或 **跳過**，或者喺 **設定 → 自動化** 下配置一個自動化，當測試變為不穩定時將其靜音或跳過，並在恢復後重新啟用。喺運行測試之前，`mix test` 會讀取項目中每個被隔離嘅測試並應用佢哋：

- **靜音**：測試會運行，其失敗仍會被報告，但如果運行中唯一嘅失敗都係靜音測試，則運行會通過。重試仍會重新運行失敗嘅靜音測試，所以不穩定測試可能通過並被報告為不穩定。
- **跳過**：測試不會運行。`mix test` 會喺運行開始前列出被跳過嘅測試。

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

如果任何非靜音測試失敗，或者 ExUnit 因為 `--max-failures` 而提前停止，運行就會像往常一樣失敗。

> [!WARNING]
> **限制**
>
> - 只有較新版本嘅 Hex 套件會應用隔離。較舊版本會像其他測試一樣運行靜音和跳過嘅測試，所以靜音測試嘅失敗仍會導致運行失敗。喺依賴佢之前，請更新 `tuist_ex`。
> - 使用 `--warnings-as-errors` 或從 umbrella 項目嘅根目錄運行時，不會應用靜音測試。佢哋嘅失敗會導致運行失敗。請改為喺 umbrella 中每個應用程式內部運行測試。
> - 跳過係根據測試嘅 describe 塊和名稱來匹配，而非其模組。另一個模組中具有相同 describe 塊和名稱嘅測試亦會被跳過。請參閱 [跳過如何選擇測試](#how-skipping-selects-tests)。
> - 當你使用 `--only`、`--include` 或 `path:line` 選擇跳過嘅測試時，或者當測試唔係用 `test` 聲明時（例如 StreamData `property`），佢仍然會運行。
> - 如果 `mix test` 無法讀取被隔離嘅測試，佢會運行每個測試並計算每次失敗。
> - 讀取被隔離嘅測試需要憑證，即使是公開項目亦然。如果運行時沒有 `TUIST_TOKEN`、`mix tuist.login` 會話或持續集成身份令牌，則不會應用任何隔離。這包括來自 fork 嘅拉取請求，佢哋通常喺沒有密鑰嘅情況下運行。
> - 使用 `--cover` 時，被跳過嘅測試會計為已移除：只有佢覆蓋嘅行會被報告為未覆蓋。
>
> `mix test` 會喺總結之後列出被錯誤遺漏嘅測試，以及仍然運行嘅被跳過測試。

### 跳過如何選擇測試 {#how-skipping-selects-tests}

被跳過嘅測試係透過对其全名應用 ExUnit 過濾器來排除嘅，例如 `--exclude "test:test create_order/2 times out"`。ExUnit 過濾器無法同時匹配模組，所以：

- 另一個模組中具有相同 describe 塊和名稱嘅測試亦會被排除。`mix test` 會喺運行之後列出這些測試。
- 當你使用 `--only`、`--include` 或 `path:line` 選擇測試時，即使佢被跳過亦會運行，因為 ExUnit 會喺排除過濾器之後應用包含過濾器。唔係用 `test` 聲明嘅測試（例如 StreamData `property`）亦然。`mix test` 會喺運行之後列出這些測試。

### 再次運行被隔離嘅測試 {#running-quarantined-tests-again}

傳遞 `--no-quarantine` 以運行每個測試並計算每次失敗，例如用於檢查修復：

```bash
mix test --no-quarantine
```

喺測試頁面將其狀態恢復為 **啟用**，以便喺後續運行中包含佢。被跳過嘅測試喺再次運行之前不會產生新結果。

如果 `mix test` 無法讀取被隔離嘅測試，佢會打印警告並運行所有測試而唔應用隔離。如果沒有憑證或已配置嘅項目，佢會運行所有測試而唔顯示警告。

Hex 套件尚未對新測試進行壓力測試。

## Slack 通知 {#slack-notifications}

透過喺你嘅 Slack 整合中設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">測試不穩定提醒</.localized_link>，即時收到測試變得不穩定嘅通知。

## 查詢不穩定狀態 {#querying}

數據可透過 HTTP 獲取。請參閱 API 參考中嘅 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以獲取完整嘅路由、過濾器和響應字段列表。要將測試案例標記或取消標記為不穩定，請發送帶有 `is_flaky` 嘅 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`，或使用 `update_test_case` Model Context Protocol 工具。
