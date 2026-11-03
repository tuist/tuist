---
{
  "title": "Rust 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Cargo 測試結果，包括 Rust doctests。"
}
---
# Rust 測試洞察 {#rust-test-insights}

Tuist 會報告來自 `cargo test` 的個別測試結果，包括單元測試、整合測試和文件測試。無需任何 Rust 依賴或額外的測試執行器。

> [!IMPORTANT] Requirements
> - 請遵循 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link>。

## 報告你的測試執行 {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

設定好 mise Cargo 包裝器後，你可以繼續輸入 `cargo test`。Cargo 仍會編譯並執行你的測試，使用其慣用的參數、輸出和退出代碼。報告失敗不會改變你的測試結果。

你可以像往常一樣選擇套件或過濾測試：

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist 追蹤的內容 {#what-is-tracked}

- 已完成測試套件中通過、失敗和被忽略的測試。
- 單元測試、整合測試和文件測試。
- 整個套件的持續時間。
- 可用的分支、提交、CI 和執行器元數據。

經過過濾的測試以及在失敗後未執行的測試，永遠不會被報告為通過。結果會顯示在儀表板的 **測試** 下方。

## 套件、模組和測試案例 {#test-hierarchy}

Tuist 按 Cargo 套件和目標將結果分組。Rust 模組路徑將目標內的個別測試分組：

| 儀表板標籤 | Rust 含義 | 範例 |
| --- | --- | --- |
| 模組 | Cargo 套件和目標 | `store::api` |
| 測試套件 | Rust 模組路徑 | `api::authentication` |
| 測試案例 | 個別測試 | `rejects_invalid_token` |

文件測試使用單獨的模組，例如 `store::doctest/store`。它們的名稱包含原始碼位置，因此移動範例可能會改變其身分識別。

## 文件測試與持續時間 {#cargo-test}

文件測試會隨你慣用的測試命令一起運行，包括 `compile_fail`、`should_panic` 和 `no_run` 範例。若只運行文件測試：

```sh
tuist cargo test --doc
```

穩定的 libtest 會報告整個套件的時間，但不報告個別測試的持續時間。不可用的計時數據會被排除在每個案例的持續時間歷史記錄和持續時間分析之外，而測試結果仍會貢獻於可靠性和執行次數。

## 報告限制 {#reporting-limits}

個別結果是從 Cargo/libtest 的預設輸出中收集的。使用 `--no-run`、`--list`、靜默或 Cargo 詳細輸出、替代格式或未捕獲的測試輸出的命令會正常運行，但不會報告個別測試。自訂測試 harness、不完整的摘要、模糊的目標歸屬以及過大的報告不會被上傳。

如果工作區套件具有同名整合目標，請使用 `-p <package>` 選擇其中一個。報告支援精確的工作區套件名稱；依賴套件、版本限定選擇器和通配符會正常執行，但不會報告。絕對文件測試路徑會被省略，以保持檢出路徑不出現在測試身分識別中。

Tuist 在收集結果時會串流輸出。這可能會影響自動顏色檢測。在 Cargo 退出後保持輸出管道開啟的背景進程可能會導致報告被省略，但不會改變 Cargo 的退出狀態。

## 可靠性與選擇 {#reliability-and-selection}

使用 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">不穩定測試檢測與隔離</.localized_link> 來調查不穩定的測試，並將它們靜音或跳過。<.localized_link href="/guides/features/test-sharding/rust">測試分片</.localized_link> 將整個 Cargo 目標分佈到 CI 工作節點上。純 Cargo 測試運行不提供覆蓋率攝取、基於覆蓋率的測試選擇和一次性構建分發。

## 疑難排解 {#troubleshooting}

如果測試執行沒有出現在儀表板中，請啟用除錯輸出以查看為何未發送其報告：

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
