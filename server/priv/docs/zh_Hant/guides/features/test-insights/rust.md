---
{
  "title": "Rust 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Cargo 測試結果，包括 Rust doctests。"
}
---
# Rust 測試洞察 {#rust-test-insights}

Tuist 會回報來自 `cargo test` 的個別測試結果，包括單元測試、整合測試與文件測試。不需要額外的 Rust 相依套件或測試執行器。

> [!IMPORTANT]
> **需求**
>
> - 請依照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 進行設定。

## 回報你的測試執行 {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

在設定好 mise Cargo 包裝器後，你可以繼續輸入 `cargo test`。Cargo 仍會以慣用的參數、輸出與結束碼來編譯並執行你的測試。回報失敗不會改變測試的結果。

你可以像往常一樣選擇套件或篩選測試：

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist 追蹤的內容 {#what-is-tracked}

- 已完成測試套件中通過、失敗與忽略的測試。
- 單元測試、整合測試與文件測試。
- 整套測試的耗時。
- 可用的分支、提交、CI 與執行器中繼資料。

經過篩選的測試以及在失敗後未執行的測試，永遠不會被回報為通過。結果會顯示在儀表板的 **測試** 底下。

## 套件、模組與測試案例 {#test-hierarchy}

Tuist 會依 Cargo 套件與目標來分組結果。Rust 模組路徑會在同一個目標內將個別測試分組：

| 儀表板標籤 | Rust 含義 | 範例 |
| --- | --- | --- |
| 模組 | Cargo 套件與目標 | `store::api` |
| 測試套件 | Rust 模組路徑 | `api::authentication` |
| 測試案例 | 個別測試 | `rejects_invalid_token` |

文件測試會使用獨立的模組，例如 `store::doctest/store`。其名稱包含原始碼位置，因此移動範例可能會改變其識別。

## 文件測試與耗時 {#cargo-test}

文件測試會隨著你慣用的測試指令一起執行，包括 `compile_fail`、`should_panic` 與 `no_run` 等範例。若只想執行文件測試：

```sh
tuist cargo test --doc
```

穩定的 libtest 會回報整套測試的時間，但不會回報個別測試的耗時。無法取得的計時資料不會納入各案例的耗時歷史與耗時分析，但測試結果仍會影響可靠性與執行次數統計。

## 回報限制 {#reporting-limits}

個別結果是從 Cargo/libtest 的預設輸出中收集。使用 `--no-run`、`--list`、安靜模式或 Cargo 詳細輸出、替代格式，或未捕捉的測試輸出的指令，會正常執行但不會回報個別測試。自訂測試驅動、不完整的摘要、模糊的目標歸屬，以及過大的報告不會被上傳。

如果工作區套件中有同名的整合目標，請使用 `-p <package>` 選擇其中一個。回報功能支援精確的工作區套件名稱；相依套件、帶版本限定符的選擇器與萬用字元會正常執行，但不會被回報。絕對的文件測試路徑會被省略，以避免將檢出路徑納入測試識別。

Tuist 會在收集結果的同時串流輸出。這可能影響自動色彩偵測。在 Cargo 結束後仍保持輸出管道開啟的背景程序，可能導致報告被省略，但不會改變 Cargo 的結束狀態。

## 可靠性與選擇 {#reliability-and-selection}

使用 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">不穩定測試偵測與隔離</.localized_link> 來調查不穩定的測試，並將它們靜音或跳過。<.localized_link href="/guides/features/test-sharding/rust">測試分片</.localized_link> 會將整個 Cargo 目標分散到 CI 工作節點上。純 Cargo 測試執行不提供涵蓋率匯入、基於涵蓋率的測試選擇，以及「建置一次」的分發功能。

## 疑難排解 {#troubleshooting}

如果測試執行沒有出現在儀表板中，請啟用除錯輸出以查看為何未送出報告：

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
