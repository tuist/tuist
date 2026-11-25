---
{
  "title": "Rust 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳 Rust 專案 Cargo 測試的行覆蓋率，並按檔案、套件及提交追蹤。"
}
---
# Rust 代碼覆蓋率 {#rust-code-coverage}

代碼覆蓋率會告訴你測試執行了代碼中的哪些行。Tuist 使用 LLVM 的源碼級覆蓋率來測量每次 `cargo test` 運行的行覆蓋率，並將一個 commit 的所有運行合併為單一數值，涵蓋整個項目、每個 package 以及每個文件。儀表板的 **Code Coverage** 頁面會按 commit 顯示這些數據，並展示每個分支的趨勢。

> [!IMPORTANT]
> **要求**
>
> - 請按照 <.localized_link href="/guides/get-started/rust-project">Rust 項目設置</.localized_link> 進行操作
> - 你 Rust 工具鏈中的 LLVM 工具（`llvm-tools`）。Tuist 會在由 rustup 管理的工具鏈中安裝它們。
> - 你的項目位於 Git 倉庫中

## 設置 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

將此內容添加到工作區根目錄的 `Cargo.toml` 中：

```toml
[workspace.metadata.tuist.test_insights.coverage]
upload = true
```

如果你改為在 `tuist.toml` 中配置 Tuist，請在其中添加 `[test_insights.coverage]` 並設置 `upload = true`。

然後照常運行你的測試：

```sh
tuist cargo test --workspace
```

Tuist 會使用 `-C instrument-coverage` 構建你倉庫中的 crates，運行測試，並隨測試結果一起上傳覆蓋率數據。測試的輸出和退出碼不會改變。若要覆蓋單次運行的設置，請設置 `TUIST_COVERAGE_UPLOAD=1` 或 `TUIST_COVERAGE_UPLOAD=0`。

覆蓋率依賴於 Tuist 在每次收集覆蓋率的運行時上傳的 Git 歷史記錄，這能將 commit 歸屬到其分支。在非 Git 倉庫中進行的運行會上傳測試結果，但不會上傳覆蓋率數據。

### 分片運行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/rust">分片運行測試</.localized_link> 時，每個開啟了覆蓋率的分片都會報告其自身 targets 的覆蓋率，Tuist 會將一次運行中的所有分片合併為單一數值。分片是有意只運行測試套件的一部分，因此不會導致 commit 的覆蓋率不完整。

### 在 CI 中完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率數據通常來自多個 job：每個分片或每個功能集對應一個 job。Tuist 無法判斷最後一個 job 何時完成報告，因此需要你明確告知。當一個 commit 的所有測試 job 都完成後，請在依賴於所有這些 job 的 job 中運行以下命令：

```sh
tuist coverage complete
```

該命令會從 checkout 的 `HEAD` 讀取 commit，即你的測試所運行的 commit；傳遞 `--commit <sha>` 可以指定另一個 commit。在 commit 標記為完成之前，其覆蓋率狀態會顯示為 **In progress**，且不會納入分支的趨勢統計中。

## 工作原理 {#how-it-works}

### Tuist 測量什麼 {#what-tuist-measures}

- **Packages。** 每個 Cargo package 都是儀表板上的一個 target，擁有各自的覆蓋率數據。
- **僅產品代碼。** 集成測試、基準測試和示例（`tests/`、`benches/` 和 `examples/` 目錄，以及這類型的 targets）屬於測試代碼。Tuist 會存儲它們，但將其排除在所有統計數值之外。`#[cfg(test)]` 模塊中的單元測試是其源文件的一部分，因此它們的行數會與源文件一起計算，如同在 `cargo llvm-cov` 中一樣。
- **Functions。** 每一行代碼都歸屬於離它最近的上層函數。無論實例化了多少種類型，泛型函數只計算一次。
- **Doctests** 會照常運行，但不會被測量。

Tuist 還會記錄每個測試二進制文件執行了哪些代碼，以便日後進行基於覆蓋率的測試選擇。`cargo test` 會在單一進程中運行二進制文件的測試，因此該記錄屬於整個二進制文件，而非其中的個別測試。

### 跳過的測試 {#skipped-tests}

當運行的參數排除了某些測試時，例如測試名稱過濾器、`--skip`、`--ignored`、`-p`、`--exclude`、`--lib` 或 `--test`，該 commit 的覆蓋率狀態將為 **Incomplete**，除非還有另一個未排除任何內容的同一 commit 運行也執行了。如果在所有測試二進制文件運行之前，`cargo test` 因失敗而停止，也會產生同樣的效果。添加 `--no-fail-fast` 以繼續運行剩餘的二進制文件。

有些測試是有意被排除的，不會導致 commit 標記為不完整：

- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">quarantine</.localized_link> 跳過的測試。** 它們被排除的方式如同已被刪除，因此僅由它們覆蓋的行會被計為未覆蓋。
- **其他分片的 targets**，當你對測試進行分片時。
- **Ignored tests**（`#[ignore]`），默認情況下不會運行。

### 未提交的更改 {#uncommitted-changes}

如果 checkout 中被追蹤的文件存在未提交的更改，則該運行測量的代碼並非屬於該 commit，因此其覆蓋率不會計入該 commit。該運行會發出警告並列出已更改的文件。CI job 在源代碼旁邊寫入的文件（例如構建輸出或覆蓋率報告），只要 Git 未追蹤它們，就不算作更改。如果只有此類運行測量了某個 commit，其覆蓋率狀態將為 **Incomplete**，且 `tuist coverage complete` 會說明原因。

### Complete 和 Incomplete 的 commits {#commit-status}

儀表板上的每個 commit 都有一個狀態：

| 狀態 | 含義 |
| --- | --- |
| In progress | 已有運行報告了覆蓋率，但 `tuist coverage complete` 尚未針對該 commit 運行。 |
| Complete | 該 commit 所有運行的測試均已執行，或已有意排除。 |
| Incomplete | 部分覆蓋率無法確定，因此該數值為下限。 |
| Not measured | 沒有運行報告該 commit 的覆蓋率。 |

分支的趨勢圖僅包含 complete 的 commits。

## 效能影響 {#performance-impact}

插樁後的代碼運行速度會稍慢。Tuist 只對你倉庫中的 crates 進行插樁：依賴項的構建方式與常規構建完全相同，並繼續從緩存中獲取。Tuist 會在 target 目錄中保留你自己 crates 的兩種變體，因此在有覆蓋率和無覆蓋率的運行之間切換時，除非代碼發生更改，否則不會重新構建它們。

## 限制 {#limitations}

- **帶有特定 target `rustflags` 的自訂 `rustc-wrapper`。** 當你的項目設置了自己的 `rustc-wrapper` 時，Tuist 會改為將 `-C instrument-coverage` 添加到 Cargo 的 `build.rustflags` 中。Cargo 配置文件中的 `target.<triple>.rustflags` 條目會替換它們，因此請自行在該處添加標誌。如果某次運行的測試未寫入任何覆蓋率數據，系統會予以說明。
- **已配置的 target runners。** Tuist 通過自己的 runner 啟動測試二進制文件。Cargo 配置文件中的 `target.<triple>.runner` 會取代它：運行的覆蓋率仍會上傳，但 Tuist 無法判斷哪個測試二進制文件執行了哪些內容。通過 `CARGO_TARGET_<TRIPLE>_RUNNER` 環境變量設置的 runner 仍可正常工作。
- **來自 fork 的 pull requests 沒有覆蓋率。** 只有通過 Tuist 身份驗證的運行才會上傳覆蓋率，而 CI 通常會扣留來自 fork 開啟的 pull requests 的秘密信息和身份令牌。

## 查詢覆蓋率 {#querying}

儀表板的 **Code Coverage** 頁面顯示每個 commit 的數值、其 packages 和 files，以及每個 file 包含的 functions。代理可以通過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link> 訪問相同的數據。
