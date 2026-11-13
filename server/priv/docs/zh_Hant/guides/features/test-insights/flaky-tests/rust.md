---
{
  "title": "Rust 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "使用 CI 歷史記錄偵測並調查不穩定的 Cargo 測試。"
}
---
# Rust 不穩定測試 {#rust-flaky-tests}

Tuist 能偵測不一致的 Cargo 測試結果，並協助你在 **測試 → 不穩定測試** 中進行調查。

> [!IMPORTANT]
> **必要條件**
>
> - 設定 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link>。

## 不穩定偵測運作方式 {#how-it-works}

Tuist 會比較同一個提交上的 CI 執行。若某項測試在一次執行中通過、在另一次執行中失敗，即可標記為不穩定。

透過慣用指令回報每次執行：

```sh
tuist cargo test --workspace
```

Cargo 不會自動重試失敗的測試。在同一個提交上重新執行 CI 工作，可提供另一筆結果以進行跨執行偵測。

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

從測試詳情頁面將測試設為靜音或略過，或在 **設定 → 自動化** 中設定隔離。下一次 `tuist cargo test` 會取得專案目前的隔離狀態：

- **靜音**測試仍會執行並回報實際結果，但其失敗不會導致指令失敗。其他測試失敗、編譯錯誤、崩潰與不完整結果仍會正常導致失敗。
- **略過**測試會被排除於執行之外，並以已隔離的略過來回報。比對包含套件、目標、Rust 模組路徑與測試名稱，因此名稱相近的測試仍保持獨立。

靜音會保留所選的工作區套件與功能，並在靜音的目標失敗後仍執行所有選取的目標。略過隔離需要選取單一套件：請使用 `tuist cargo test -p store`，而非多套件工作區指令。Tuist 拒絕多套件略過，因為縮減指令範圍可能改變 Cargo 的统一相依性功能。

隔離也適用於 <.localized_link href="/guides/features/test-sharding/rust">分片的 Cargo 執行</.localized_link>。若 Tuist 無法取得狀態，會發出警告並在不啟用隔離的情況下執行；失敗不會被抑制。若要刻意在不啟用隔離的情況下執行：

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

### 限制 {#limitations}

- 強制執行需要標準 libtest 測試 harness 與預設擷取輸出。當需要套用隔離時，使用安靜、詳細、替代格式或未擷取輸出的指令會失敗。
- 若目標歸屬不明確，請使用 `-p <package>` 選取精確的工作區套件。不支援自訂 harness、套件/目標名稱萬用字元，以及未解析的套件選擇。
- 文件測試也可設為靜音或略過，但 Rustdoc 的測試過濾無法區分每組可能的範例名稱。若略過某個範例也會略過已啟用的範例，或部分文件測試排除使用 `--exact`，Tuist 會以診斷訊息失敗，而不會執行被略過的範例或靜默省略已啟用的測試。調查期間請使用上述覆寫。

## 壓力測試新測試 {#stress-testing-new-tests}

Tuist 不會對新的 Cargo 測試進行壓力測試。調查失敗測試時，可使用 Cargo 測試過濾器重複執行該測試：

```sh
tuist cargo test -p store rejects_invalid_token
```

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
