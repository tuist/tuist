---
{
  "title": "Rust Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Cargo test results, including Rust doctests, in the Tuist dashboard."
}
---
# Rust 測試洞察 {#rust-test-insights}

Tuist 會回報來自 `cargo test` 的個別測試結果，包括單元測試、整合測試和文件測試。不需要額外的 Rust 依賴或測試執行器。

> [!IMPORTANT] Requirements
> - 請遵循 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link>。

## 回報您的測試執行 {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

設定好 mise Cargo 包裝器後，您可以繼續輸入 `cargo test`。Cargo 仍會編譯並執行您的測試，保留其慣用的參數、輸出和結束代碼。回報失敗不會改變測試結果。

您可以像往常一樣選擇套件或篩選測試：

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist 追蹤的內容 {#what-is-tracked}

- 來自已完成測試套件的通過、失敗和忽略的測試。
- 單元測試、整合測試和文件測試。
- 整個套件的耗時。
- 可用的分支、提交、CI 和執行器中繼資料。

經過篩選的測試以及在失敗後未執行的測試永遠不會被回報為通過。結果會顯示在儀表板的 **測試** 下方。

## 套件、模組和測試案例 {#test-hierarchy}

Tuist 會依 Cargo 套件和目標將結果分組。Rust 模組路徑會在目標內將個別測試分組：

| 儀表板標籤 | Rust 含義 | 範例 |
| --- | --- | --- |
| 模組 | Cargo 套件和目標 | `store::api` |
| 測試套件 | Rust 模組路徑 | `api::authentication` |
| 測試案例 | 個別測試 | `rejects_invalid_token` |

文件測試使用獨立的模組，例如 `store::doctest/store`。它們的名稱包含原始碼位置，因此移動範例可能會改變其識別資訊。

## 文件測試與耗時 {#cargo-test}

文件測試會使用您慣用的測試指令執行，包括 `compile_fail`、`should_panic` 和 `no_run` 範例。若只執行文件測試：

```sh
tuist cargo test --doc
```

穩定的 libtest 會回報整個套件的耗時，但不會回報個別測試的耗時。無法取得的計時資料不會納入個別案例的耗時歷史記錄和耗時分析中，但測試結果仍會影響可靠性和執行次數統計。

## 回報限制 {#reporting-limits}

個別結果是從 Cargo/libtest 的預設輸出中收集的。使用 `--no-run`、`--list`、靜默或詳細 Cargo 輸出、替代格式或未擷取測試輸出的指令會正常執行，但不會回報個別測試。自訂測試驅動程式、不完整的摘要、模糊的目標歸屬以及過大的報告不會被上傳。

如果工作區套件具有相同名稱的整合目標，請使用 `-p <package>` 選擇其中一個。回報功能支援精確的工作區套件名稱；依賴套件、版本限定選擇器和萬用字元會正常執行，但不會被回報。絕對文件測試路徑會被省略，以避免簽出路徑進入測試識別資訊中。

Tuist 會在收集結果時串流輸出。這可能會影響自動顏色偵測。在 Cargo 結束後仍保持輸出管道開啟的背景處理程序可能會導致報告被省略，但不會改變 Cargo 的結束狀態。

## 可靠性與選擇 {#reliability-and-selection}

使用 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">不穩定測試偵測與隔離</.localized_link> 來調查不穩定的測試，並將它們靜音或跳過。<.localized_link href="/guides/features/test-sharding/rust">測試分片</.localized_link> 會將整個 Cargo 目標分散到 CI 工作節點上。涵蓋率匯入、基於涵蓋率的測試選擇以及一次建置分散功能不適用於單純的 Cargo 測試執行。

## 疑難排解 {#troubleshooting}

如果測試執行沒有出現在儀表板中，請啟用除錯輸出以查看為何未傳送其報告：

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
