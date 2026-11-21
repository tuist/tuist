---
{
  "title": "Rust 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "使用 CI 歷史記錄偵測並調查不穩定的 Cargo 測試。"
}
---
# Rust 不穩定測試 {#rust-flaky-tests}

Tuist 可以偵測不一致的 Cargo 測試結果，並協助你在 **測試 → 不穩定測試** 中調查。

> [!IMPORTANT]
> **要求**
>
> - 設定 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>。

## 不穩定偵測如何運作 {#how-it-works}

Tuist 會比較同一個 commit 上的 CI 執行。如果一個測試在一次執行中通過，而在另一次執行中失敗，就可以標記為不穩定。

透過常用指令報告每次執行：

```sh
tuist cargo test --workspace
```

Cargo 不會自動重試失敗的測試。在同一個 commit 上重新執行 CI 工作可提供另一個結果，用於跨執行偵測。

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

從測試的詳細頁面將其靜音或跳過，或在 **設定 → 自動化** 中設定隔離。下一個 `tuist cargo test` 會擷取專案目前的隔離狀態：

- **靜音** 測試仍會執行並報告實際結果，但其失敗不會導致指令失敗。其他測試失敗、編譯錯誤、崩潰和不完整結果仍會正常導致失敗。
- **已跳過** 測試會被排除在執行之外，並報告為已隔離的跳過。比對包括套件、目標、Rust 模組路徑和測試名稱，因此名稱相似的測試仍保持獨立。

靜音會保留所選的工作區套件和功能，並執行所有選定的目標，即使在靜音目標失敗後亦然。跳過隔離需要選擇一個套件：使用 `tuist cargo test -p store` 而非多套件工作區指令。Tuist 拒絕多套件跳過，因為縮小指令範圍可能會改變 Cargo 的統一相依性功能。

隔離也適用於 <.localized_link href="/guides/features/test-sharding/rust">分片的 Cargo 執行</.localized_link>。如果 Tuist 無法擷取狀態，它會發出警告並在沒有隔離的情況下執行；失敗不會被抑制。若要刻意在沒有隔離的情況下執行：

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

### 限制 {#limitations}

- 強制執行需要標準的 libtest harness 和捕獲的預設輸出。當需要套用隔離時，具有安靜、詳細、替代格式或未捕獲輸出的指令會失敗。
- 如果目標歸屬不明確，請使用 `-p <package>` 選擇精確的工作區套件。不支援自訂 harness、套件/目標名稱 glob 和未解析的套件選擇。
- Doctests 也可以被靜音或跳過，但 Rustdoc 的測試過濾無法區分每一對可能的範例名稱。如果跳過一個範例也會跳過一個已啟用的範例，或者部分 doctest 排除使用 `--exact`，Tuist 會以診斷訊息失敗，而不是執行被跳過的範例或靜默省略已啟用的測試。在調查期間使用上述覆寫。

## 壓力測試新測試 {#stress-testing-new-tests}

Tuist 不會對新的 Cargo 測試進行壓力測試。使用 Cargo 測試過濾器來重複失敗的測試，以便在調查時進行：

```sh
tuist cargo test -p store rejects_invalid_token
```

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
