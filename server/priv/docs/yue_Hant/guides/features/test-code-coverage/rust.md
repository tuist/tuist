---
{
  "title": "Rust 程式碼覆蓋率",
  "titleTemplate": ":title · 程式碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳 Rust 專案 Cargo 測試的逐行覆蓋率，並按檔案、套件及提交追蹤。"
}
---
# Rust 程式碼覆蓋率 {#rust-code-coverage}

程式碼覆蓋率告訴你測試執行了你程式碼中的哪些行。Tuist 使用 LLVM 的原始碼基礎覆蓋率來測量每次 `cargo test` 執行的行覆蓋率，並將一個 commit 的所有執行合併為單一數值，適用於整個專案、每個套件以及每個檔案。儀表板的 **程式碼覆蓋率** 頁面會顯示每個 commit 的數據，以及每個分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 請遵循 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link>
> - 你 Rust 工具鏈中的 LLVM 工具（`llvm-tools`）。Tuist 會在 rustup 管理的工具鏈上安裝它們。
> - 你的專案位於 Git 儲存庫中

## 設定 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

將此內容加入 workspace 根目錄的 `Cargo.toml`：

```toml
[workspace.metadata.tuist.test_insights.coverage]
upload = true
```

如果你改為在 `tuist.toml` 中設定 Tuist，請在該處加入 `[test_insights.coverage]` 並設定 `upload = true`。

然後照常執行你的測試：

```sh
tuist cargo test --workspace
```

Tuist 會使用 `-C instrument-coverage` 編譯你儲存庫中的 crates、執行測試，並連同測試結果一起上傳覆蓋率數據。你的測試輸出和退出碼不會改變。若要覆寫單次執行的設定，請設定 `TUIST_COVERAGE_UPLOAD=1` 或 `TUIST_COVERAGE_UPLOAD=0`。

覆蓋率依賴 Tuist 在每次收集覆蓋率的執行時上傳的 Git 歷史記錄，這能將 commit 歸類到其分支。在非 Git 儲存庫中進行的執行會上傳測試結果，但不會上傳覆蓋率。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/rust">將測試分片</.localized_link> 時，每個開啟覆蓋率的分片都會報告其自身目標的覆蓋率，而 Tuist 會將一次執行的所有分片合併為單一數值。分片故意只執行測試套件的一部分，因此不會導致 commit 的覆蓋率不完整。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個工作：每個分片或每組功能各有一個工作。Tuist 無法判斷最後一個工作何時已完成報告，所以你需要告訴它。當一個 commit 的所有測試工作都完成後，在依賴所有這些工作的另一個工作中執行以下指令：

```sh
tuist cargo coverage-complete
```

該指令會從 checkout 的 `HEAD` 讀取 commit，即你的測試所運行的 commit；傳遞 `--commit <sha>` 以指定另一個 commit。在 commit 完成之前，其覆蓋率會顯示為 **進行中**，且不會納入該分支的趨勢計算。

## 運作原理 {#how-it-works}

### Tuist 測量的內容 {#what-tuist-measures}

- **套件。** 每個 Cargo 套件都是儀表板上的一個目標，擁有各自的覆蓋率。
- **僅產品程式碼。** 整合測試、基準測試和範例（`tests/`、`benches/` 和 `examples/` 目錄，以及這類型的目標）屬於測試程式碼。Tuist 會儲存它們，但將其排除在所有數值之外。`#[cfg(test)]` 模組中的單元測試是其原始檔的一部分，因此它們的行數會與原始檔一同計算，如同在 `cargo llvm-cov` 中一樣。
- **函式。** 每一行都歸屬於在其上方最近開始的函式。泛型函式無論實例化了多少種類型，都只計算一次。
- **文件測試** 會照常執行，但不會被測量。

Tuist 還會記錄每個測試二進位檔執行了哪些程式碼，以便日後進行基於覆蓋率的測試選擇。`cargo test` 會在單一程序中執行二進位檔的測試，因此該記錄屬於整個二進位檔，而非其個別測試。

### 略過的測試 {#skipped-tests}

當執行本身的參數略過了某些測試，例如測試名稱過濾器、`--skip`、`--ignored`、`-p`、`--exclude`、`--lib` 或 `--test`，該 commit 的覆蓋率會顯示為 **不完整**，除非還有另一個未略過任何內容的同一 commit 執行也運行了。如果在每個測試二進位檔運行之前就因失敗而停止 `cargo test`，也會產生相同效果。請加入 `--no-fail-fast` 以繼續運行剩餘的二進位檔。

有些測試是故意被略過的，不會導致 commit 不完整：

- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">隔離</.localized_link> 略過的測試。** 它們被略過的方式如同已被移除，因此只有它們覆蓋的行數會被計為未覆蓋。
- **其他分片的目標**，當你將測試分片時。
- **忽略的測試**（`#[ignore]`），預設情況下不會運行。

### 未提交的變更 {#uncommitted-changes}

如果從一個含有未提交變更的追蹤檔案的 checkout 進行執行，所測量的程式碼並非該 commit 的內容，因此其覆蓋率不會計入該 commit。該執行會發出警告並列出已變更的檔案。CI 工作在原始碼旁邊寫入的檔案（例如建構輸出或覆蓋率報告），只要 Git 未追蹤它們，就不算作變更。如果只有這類執行測量了某個 commit，其覆蓋率會顯示為 **不完整**，而 `tuist cargo coverage-complete` 會說明原因。

### 完整與不完整的 commit {#commit-status}

儀表板上的每個 commit 都有一個狀態：

| 狀態 | 意義 |
| --- | --- |
| 進行中 | 已有執行報告了覆蓋率，但尚未針對該 commit 執行 `tuist cargo coverage-complete`。 |
| 完整 | 該 commit 所有執行的測試都已運行，或是故意被略過。 |
| 不完整 | 部分覆蓋率無法確定，因此該數值為下限。 |
| 未測量 | 沒有執行回報該 commit 的覆蓋率。 |

分支的趨勢僅包含完整的 commit。

## 效能影響 {#performance-impact}

插樁後的程式碼運行速度會稍慢。Tuist 只會對你儲存庫中的 crate 進行插樁：依賴項目的建構方式與一般建構完全相同，並繼續從快取中取得。Tuist 會在 target 目錄中保留你自己 crate 的兩種變體，因此在有無覆蓋率的執行之間切換時，除非程式碼有所變更，否則不會重新建構它們。

## 限制 {#limitations}

- **自訂 `rustc-wrapper` 搭配特定目標的 `rustflags`。** 當你的專案設定自己的 `rustc-wrapper` 時，Tuist 會改為將 `-C instrument-coverage` 加入 Cargo 的 `build.rustflags`。Cargo 設定檔中的 `target.<triple>.rustflags` 項目會取代它們，因此請自行在該處加入旗標。如果某次執行的測試未寫入任何覆蓋率資料，系統會顯示此訊息。
- **已設定的目標執行器。** Tuist 會透過自己的執行器啟動測試二進位檔。Cargo 設定檔中的 `target.<triple>.runner` 會取代它：執行的覆蓋率仍會上傳，但 Tuist 無法得知哪個測試二進位檔執行了哪些內容。透過 `CARGO_TARGET_<TRIPLE>_RUNNER` 環境變數設定的執行器則可繼續正常運作。
- **來自分叉的 Pull Request 沒有覆蓋率。** 只有通過 Tuist 驗證的執行才會上傳覆蓋率，而 CI 通常會對來自分叉的 Pull Request 隱藏密鑰和身分識別令牌。

## 查詢覆蓋率 {#querying}

儀表板的 **程式碼覆蓋率** 頁面顯示每個 commit 的數值、其套件及其檔案，以及每個檔案所包含的函式。代理程式亦可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 存取相同的資料。
