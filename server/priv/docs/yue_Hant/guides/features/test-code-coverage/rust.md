---
{
  "title": "Rust 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "上載你 Rust 專案 Cargo 測試嘅行覆蓋率，並按檔案、套件同提交追蹤。"
}
---
# Rust 代碼覆蓋率 {#rust-code-coverage}

代碼覆蓋率會告訴你測試執行了你代碼中的哪些行。Tuist 使用 LLVM 的源碼基礎覆蓋率來測量每次 `cargo test` 運行的行覆蓋率，並將一個 commit 的所有運行合併為一個數字，涵蓋整個項目、每個 package 和每個文件。儀表板的 **代碼覆蓋率** 頁面會按 commit 顯示，並作為每個分支的趨勢呈現。

> [!IMPORTANT]
> **要求**
>
> - 請按照 <.localized_link href="/guides/get-started/rust-project">Rust 項目設置</.localized_link>
> - 你的 Rust 工具鏈中的 LLVM 工具（`llvm-tools`）。Tuist 會在由 rustup 管理的工具鏈上安裝它們。
> - 你的項目位於 Git 倉庫中

## 設置 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

將此添加到 workspace 根目錄的 `Cargo.toml`：

```toml
[workspace.metadata.tuist.test_insights.coverage]
upload = true
```

如果你改為在 `tuist.toml` 中配置 Tuist，請在那裡添加 `[test_insights.coverage]` 並設置 `upload = true`。

然後照常運行你的測試：

```sh
tuist cargo test --workspace
```

Tuist 會使用 `-C instrument-coverage` 構建你倉庫中的 crates，運行測試，並隨測試結果一起上傳覆蓋率數據。你的測試輸出和退出代碼不會改變。若要覆蓋單次運行的設置，請設置 `TUIST_COVERAGE_UPLOAD=1` 或 `TUIST_COVERAGE_UPLOAD=0`。

覆蓋率依賴於 Tuist 在每次收集覆蓋率的運行時上傳的 Git 歷史記錄，這會將 commit 定位到其分支上。在非 Git 倉庫中進行的運行會上傳測試結果，但不會上傳覆蓋率。

### 分片運行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/rust">分片你的測試</.localized_link> 時，每個開啟覆蓋率運行的分片都會報告其自身 targets 的覆蓋率，而 Tuist 會將一次運行的所有分片合併為一個數字。分片有意只運行套件的一部分，因此不會導致 commit 的覆蓋率不完整。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個 job：每個分片或每個功能集對應一個。Tuist 無法判斷最後一個是否已報告，所以你需要告訴它。當一個 commit 的所有測試 job 都完成後，在依賴於所有這些 job 的一個 job 中運行以下命令：

```sh
tuist cargo coverage-complete
```

該命令從 checkout 的 `HEAD` 讀取 commit，即你的測試所運行的 commit；傳遞 `--commit <sha>` 以指定另一個 commit。在 commit 完成之前，其覆蓋率會顯示為 **進行中**，並且不會納入其分支的趨勢中。

## 工作原理 {#how-it-works}

### Tuist 測量什麼 {#what-tuist-measures}

- **Packages。** 每個 Cargo package 都是儀表板上的一個 target，擁有自己的覆蓋率。
- **僅產品代碼。** 集成測試、基準測試和示例（`tests/`、`benches/` 和 `examples/` 目錄，以及這類型的 targets）屬於測試代碼。Tuist 會存儲它們，但將其排除在所有數字之外。`#[cfg(test)]` 模塊中的單元測試是其源文件的一部分，因此它們的行數會與源文件一起計算，就像在 `cargo llvm-cov` 中一樣。
- **函數。** 每一行都歸屬於在其上方最近開始的函數。無論實例化了多少種類型，泛型函數只計數一次。
- **Doctests** 照常運行，但不會被測量。

Tuist 還會記錄每個測試二進制文件執行了哪些代碼，以便後續進行基於覆蓋率的測試選擇。`cargo test` 在一個進程中運行二進制文件的測試，因此該記錄屬於整個二進制文件，而不是其單獨的測試。

### 跳過的測試 {#skipped-tests}

當運行的參數排除某些測試時，例如測試名稱過濾器、`--skip`、`--ignored`、`-p`、`--exclude`、`--lib` 或 `--test`，commit 的覆蓋率將顯示為 **不完整**，除非該 commit 還有另一個未排除任何內容的運行也執行了。如果在每個測試二進制文件運行之前就停止 `cargo test` 的失敗也會產生相同的效果。添加 `--no-fail-fast` 以繼續運行剩餘的二進制文件。

有些測試是故意被排除的，不會導致 commit 不完整：

- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">隔離</.localized_link> 跳過的測試。** 它們被排除在外，就像已被刪除一樣，因此只有它們覆蓋的行會被計為未覆蓋。
- **其他分片的 targets**，當你對測試進行分片時。
- **被忽略的測試**（`#[ignore]`），默認情況下不會運行。

### 完整和不完整的 commits {#commit-status}

儀表板上的每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 運行已報告覆蓋率，但 `tuist cargo coverage-complete` 尚未針對該 commit 運行。 |
| 完整 | 該 commit 運行的所有測試都已執行，或是故意被排除。 |
| 不完整 | 部分覆蓋率無法確定，因此該數字僅為下限。 |
| 未測量 | 沒有運行報告該 commit 的覆蓋率。 |

分支的趨勢僅包含完整的 commits。

## 性能影響 {#performance-impact}

插樁後的代碼運行速度會稍慢。Tuist 僅對你倉庫中的 crates 進行插樁：依賴項的構建方式與常規構建完全相同，並繼續從緩存中獲取。Tuist 會在 target 目錄中保留你自己 crates 的兩種變體，因此在有覆蓋率和無覆蓋率的運行之間切換時，除非代碼發生更改，否則不會重新構建它們。

## 限制 {#limitations}

- **帶有特定 target `rustflags` 的自定義 `rustc-wrapper`。** 當你的項目設置自己的 `rustc-wrapper` 時，Tuist 會改為將 `-C instrument-coverage` 添加到 Cargo 的 `build.rustflags` 中。Cargo 配置文件中的 `target.<triple>.rustflags` 條目會替換它們，因此請自行在那裡添加該標誌。如果運行的測試沒有寫入任何覆蓋率數據，系統會予以說明。
- **已配置的 target runners。** Tuist 通過自己的 runner 啟動測試二進制文件。Cargo 配置文件中的 `target.<triple>.runner` 會取代它：運行的覆蓋率仍會上傳，但 Tuist 無法判斷哪個測試二進制文件執行了什麼內容。通過 `CARGO_TARGET_<TRIPLE>_RUNNER` 環境變量設置的 runner 仍可正常工作。
- **來自 fork 的 pull requests 沒有覆蓋率。** 只有經過 Tuist 身份驗證的運行才會上傳覆蓋率，而 CI 通常會扣留來自 fork 的 pull requests 的秘密和身份令牌。

## 查詢覆蓋率 {#querying}

儀表板的 **Code Coverage** 頁面顯示每個 commit 的數字、其 packages 和文件，以及每個文件包含的函數。代理可以通過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link> 訪問相同的數據。
