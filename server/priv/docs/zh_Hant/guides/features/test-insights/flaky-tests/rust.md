---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust 不穩定測試 {#rust-flaky-tests}

Tuist 可以偵測不一致的 Cargo 測試結果，並協助您在 **測試 → 不穩定測試** 中進行調查。

> [!IMPORTANT] Requirements
> - 設定 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link>。

## 不穩定測試偵測運作方式 {#how-it-works}

Tuist 會比較同一個提交上的 CI 執行結果。若某項測試在一次執行中通過，而在另一次執行中失敗，則可標記為不穩定。

透過慣用指令回報每次執行：

```sh
tuist cargo test --workspace
```

Cargo 不會自動重試失敗的測試。在同一個提交上重新執行 CI 工作可提供另一個結果，用於跨執行偵測。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測與復原會透過專案的「不穩定測試偵測」自動化流程執行。預設情況下，若 14 天內未再次觸發，不穩定標記將會清除。您可以在 **設定 → 自動化** 下編輯復原時間範圍與動作。

### 手動管理

開啟 **測試 → 不穩定測試** 以檢視測試歷史記錄。您可以從其詳細資訊頁面手動標記或取消標記為不穩定。

## 隔離與壓力測試 {#quarantine}

Cargo 整合尚未套用隔離：在儀表板中靜音或略過的測試仍會執行，且其失敗仍會影響結果。它也不會對新測試進行壓力測試。在調查失敗測試時，請使用 Cargo 測試篩選器來重複執行該測試：

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 通知 {#notifications}

設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack 不穩定測試警示</.localized_link>，以便在測試變為不穩定時通知您的團隊。
