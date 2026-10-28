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

Tuist 會比較同一個 commit 上的 CI 執行結果。如果在一次執行中通過而在另一次執行中失敗的測試，可能會被標記為不穩定。

透過常用指令回報每次執行：

```sh
tuist cargo test --workspace
```

Cargo 不會自動重試失敗的測試。在同一個 commit 上重新執行 CI 工作可提供另一個結果，以便進行跨執行偵測。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測與恢復會透過專案的「Flaky test detection」自動化流程執行。預設情況下，如果 14 天內沒有重新觸發，不穩定標記將會清除。你可以在 **Settings → Automations** 下編輯恢復時間範圍和動作。

### 手動管理

開啟 **Tests → Flaky Tests** 以檢查測試的歷史記錄。你可以從其詳細資訊頁面手動將其標記或取消標記為不穩定。

## 隔離與壓力測試 {#quarantine}

從測試的詳細資訊頁面將測試靜音或跳過，或在 **Settings → Automations** 中設定隔離。下一次 `tuist cargo test` 會抓取專案目前的隔離狀態：

- **靜音**測試仍會執行並回報實際結果，但其失敗不會導致指令失敗。其他測試失敗、編譯錯誤、當機和不完整結果仍會正常導致失敗。
- **已跳過**測試會被排除在執行之外，並回報為已隔離的跳過。匹配條件包括套件、目標、Rust 模組路徑和測試名稱，因此名稱相似的測試仍保持獨立。

靜音會保留所選的工作區套件和功能，並執行所有選定的目標，即使靜音的目標失敗亦然。跳過隔離需要選擇一個套件：使用 `tuist cargo test -p store` 而非多套件工作區指令。Tuist 拒絕多套件跳過，因為縮小指令範圍可能會改變 Cargo 的統一依賴功能。

隔離也適用於 <.localized_link href="/guides/features/test-sharding/rust">sharded Cargo runs</.localized_link>。如果 Tuist 無法抓取狀態，它會發出警告並在沒有隔離的情況下執行；失敗不會被抑制。若要刻意在沒有隔離的情況下執行：

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

強制執行需要標準的 libtest harnesses 和捕獲的預設輸出。當需要應用隔離時，具有安靜、詳細、替代格式或未捕獲輸出的指令會失敗。如果目標歸屬不明確，請使用 `-p <package>` 選擇精確的工作區套件。自訂 harnesses、套件/目標名稱 glob 和未解析的套件選擇不受支援。Doctests 也可以靜音或跳過，但 Rustdoc 的測試過濾無法區分每對可能的範例名稱。如果跳過一個範例也會跳過一個已啟用的範例，或部分 doctest 排除使用 `--exact`，Tuist 會失敗並提供診斷訊息，而不是執行已跳過的範例或靜默省略已啟用的測試；在調查期間請使用上述覆蓋方法。

Tuist 不會對新的 Cargo 測試進行壓力測試。使用 Cargo 測試過濾器來重複失敗的測試，以便在調查時進行：

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 通知 {#notifications}

設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link>，以便在測試變得不穩定時通知你的團隊。
