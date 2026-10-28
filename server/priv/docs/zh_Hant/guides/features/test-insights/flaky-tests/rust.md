---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust 不穩定測試 {#rust-flaky-tests}

Tuist 可以偵測不一致的 Cargo 測試結果，並協助您在 **Tests → Flaky Tests** 中進行調查。

> [!IMPORTANT] Requirements
> - 設定 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>。

## 不穩定偵測的運作方式 {#how-it-works}

Tuist 會比較相同提交上的 CI 執行結果。若一項測試在一次執行中通過，而在另一次執行中失敗，則可標記為不穩定。

透過慣用指令回報每次執行：

```sh
tuist cargo test --workspace
```

Cargo 不會自動重試失敗的測試。在相同提交上重新執行 CI 工作可提供另一筆結果，以便進行跨執行偵測。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測與復原會透過專案的「Flaky test detection」自動化流程執行。預設情況下，若在 14 天內未再次觸發，不穩定標記將會清除。您可以在 **Settings → Automations** 下編輯復原時間範圍與動作。

### 手動管理

開啟 **Tests → Flaky Tests** 以檢視測試歷史記錄。您可以從其詳細資訊頁面手動標記或取消標記為不穩定。

## 隔離與壓力測試 {#quarantine}

從測試的詳細資訊頁面將測試靜音或略過，或在 **Settings → Automations** 中設定隔離。下一個 `tuist cargo test` 會取得專案目前的隔離狀態：

- **已靜音** 的測試仍會執行並回報實際結果，但其失敗不會導致指令失敗。其他測試失敗、編譯錯誤、崩潰以及不完整的結果仍會正常導致失敗。
- **已略過** 的測試會被排除於執行之外，並以隔離略過來回報。比對範圍包含套件、目標、Rust 模組路徑與測試名稱，因此名稱相似的測試仍保持獨立。

靜音會保留所選的工作區套件與功能，並在已靜音的目標失敗後仍執行所有選取的目標。略過隔離需要選取單一套件：請使用 `tuist cargo test -p store`，而非多套件工作區指令。Tuist 拒絕多套件略過，因為縮減指令範圍可能會改變 Cargo 的統一相依性功能。

隔離也適用於 <.localized_link href="/guides/features/test-sharding/rust">分片執行的 Cargo 測試</.localized_link>。若 Tuist 無法取得狀態，它會發出警告並在無隔離的情況下執行；失敗不會被抑制。若要刻意在無隔離的情況下執行：

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

強制執行需要標準 libtest harness 與捕獲的預設輸出。當需要套用隔離時，使用安靜、詳盡、替代格式或未捕獲輸出的指令會失敗。若目標歸屬不明確，請使用 `-p <package>` 選取精確的工作區套件。不支援自訂 harness、套件/目標名稱萬用字元，以及未解析的套件選取。Doctest 也可以靜音或略過，但 Rustdoc 的測試過濾無法區分每組可能的範例名稱。若略過某個範例也會略過已啟用的範例，或部分 doctest 排除使用 `--exact`，Tuist 會以診斷訊息失敗，而不會執行被略過的範例或靜默省略已啟用的測試；在調查期間請使用上述覆寫。

Tuist 不會對新的 Cargo 測試進行壓力測試。在調查失敗測試時，請使用 Cargo 測試過濾器來重複執行該測試：

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 通知 {#notifications}

設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack 不穩定測試警示</.localized_link>，以便在測試變為不穩定時通知您的團隊。
