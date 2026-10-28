---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust 不穩定測試 {#rust-flaky-tests}

Tuist 可以偵測不一致的 Cargo 測試結果，並協助你在 **Tests → Flaky Tests** 中進行調查。

> [!IMPORTANT] Requirements
> - 設定 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>。

## 不穩定測試偵測如何運作 {#how-it-works}

Tuist 會比較同一個 commit 上的 CI 執行結果。如果一個測試在一次執行中通過，而在另一次執行中失敗，則可能被標記為不穩定。

透過常規命令報告每次執行：

```sh
tuist cargo test --workspace
```

Cargo 不會自動重試失敗的測試。在同一個 commit 上重新執行 CI 工作可提供另一個結果以進行跨執行偵測。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測和恢復透過專案的「Flaky test detection」自動化執行。預設情況下，如果在 14 天內沒有重新觸發，不穩定標記將被清除。你可以在 **Settings → Automations** 下編輯恢復時間範圍和動作。

### 手動管理

開啟 **Tests → Flaky Tests** 以檢查測試的歷史記錄。你可以從其詳細頁面手動將其標記為或取消標記為不穩定。

## 隔離與壓力測試 {#quarantine}

Cargo 整合尚未應用隔離：在儀表板中被靜音或跳過的測試仍然會執行，並且它們的失敗仍然會影響結果。它也不會對新測試進行壓力測試。使用 Cargo 測試過濾器來重複執行失敗的測試，以便在調查時進行：

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 通知 {#notifications}

設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link>，以便在測試變得不穩定時通知你的團隊。
