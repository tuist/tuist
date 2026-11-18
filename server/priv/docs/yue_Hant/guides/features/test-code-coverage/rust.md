---
{
  "title": "Rust 程式碼涵蓋率",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳 Rust 專案 Cargo 測試的程式碼涵蓋率，並按檔案、套件及提交記錄追蹤。"
}
---
# Rust 程式碼覆蓋率 {#rust-code-coverage}

程式碼覆蓋率會告訴你測試執行了你程式碼中的哪些行。Tuist 使用 LLVM 的原始碼基礎覆蓋率來測量每次 `cargo test` 執行的行覆蓋率，並將一個 commit 的所有執行結果合併為單一數值，適用於整個專案、每個套件以及每個檔案。儀表板的 **程式碼覆蓋率** 頁面會按 commit 顯示，並呈現每個分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 請遵循 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link>
> - 你的 Rust 工具鏈中的 LLVM 工具（`llvm-tools`）。Tuist 會在由 rustup 管理的工具鏈上安裝這些工具。
> - 你的專案位於 Git 儲存庫中

## 設定 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

將以下內容新增至你儲存庫根目錄的 `tuist.toml`：

```toml
[test_insights.coverage]
upload = true
```

然後照常執行你的測試：

```sh
tuist cargo test --workspace
```

Tuist 會使用 `-C instrument-coverage` 編譯你儲存庫中的 crates、執行測試，並連同該次執行的測試結果一起上傳覆蓋率資料。你的測試輸出與結束代碼不會改變。若要覆寫單次執行的設定，請設定 `TUIST_COVERAGE_UPLOAD=1` 或 `TUIST_COVERAGE_UPLOAD=0`。

覆蓋率依賴 Tuist 在每次收集覆蓋率的執行中上傳的 Git 歷史記錄，這會將 commit 歸屬於其所在分支。在非 Git 儲存庫中進行的執行會上傳測試結果，但不會上傳覆蓋率。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/rust">將測試分片</.localized_link> 時，每個開啟覆蓋率的分片都會回報其自身目標的覆蓋率，而 Tuist 會將一次執行的所有分片合併為單一數值。分片是刻意只執行測試套件的一部分，因此不會導致該 commit 的覆蓋率不完整。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個工作：每個分片或每組功能各一個工作。Tuist 無法判斷最後一個工作何時已完成回報，因此需要你明確告知。當某個 commit 的所有測試工作都完成後，请在依賴所有這些工作的另一個工作中執行以下指令：

```sh
tuist cargo coverage-complete
```

該指令會從 checkout 中讀取 commit，或讀取你的 CI 供應商在 pull request 上所回報的 commit；若要指定其他 commit，請傳遞 `--commit <sha>`。在 commit 標記為完成之前，其覆蓋率會顯示為 **進行中**，且不會納入該分支的趨勢計算。

## 運作方式 {#how-it-works}

### Tuist 測量的內容 {#what-tuist-measures}

- **套件。** 每個 Cargo 套件在儀表板上都是一個目標，並擁有各自的覆蓋率。
- **僅限產品程式碼。** 整合測試、基準測試和範例（`tests/`、`benches/` 和 `examples/` 目錄，以及這類型的目標）屬於測試程式碼。Tuist 會儲存它們，但不會將其納入任何數值計算。`#[cfg(test)]` 模組中的單元測試是其原始檔的一部分，因此這些行會與該檔案一併計入，如同 `cargo llvm-cov` 的做法。
- **函式。** 每一行都歸屬於在其上方最近開始的函式。泛型函式無論實作了多少種類型，都只計算一次。
- **文件測試**會照常執行，但不會被測量。

Tuist 也會記錄每個測試二元檔執行了哪些程式碼，以便日後進行基於覆蓋率的測試選擇。`cargo test` 會在單一程序中執行二元檔的所有測試，因此該記錄屬於整個二元檔，而非其個別測試。

### 已略過的測試 {#skipped-tests}

當執行本身的參數排除了某些測試（例如測試名稱篩選器、`--skip`、`--ignored`、`-p`、`--exclude`、`--lib` 或 `--test`），該 commit 的覆蓋率會標示為 **不完整**，除非另有另一個未排除任何內容的同一 commit 執行也同時運行。若發生失敗導致 `cargo test` 在所有測試二元檔執行前就中止，也會產生相同效果。請加入 `--no-fail-fast` 以繼續執行剩餘的二元檔。

有些測試是刻意被排除，且不會導致 commit 變得不完整：

- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">隔離</.localized_link> 略過的測試。** 它們會被視為已移除，因此只有這些測試覆蓋到的行會被計為未覆蓋。
- **其他分片的目標**，當你將測試分片時。
- **被忽略的測試**（`#[ignore]`），預設不會執行。

### 完整與不完整的 commit {#commit-status}

儀表板上的每個 commit 都有狀態：

| 狀態 | 意義 |
| --- | --- |
| 進行中 | 已有執行回報覆蓋率，但 `tuist cargo coverage-complete` 尚未針對該 commit 執行。 |
| 完整 | 該 commit 所有執行的測試都已執行，或是被刻意排除。 |
| 不完整 | 部分覆蓋率無法確定，因此該數值為下限。 |
| 未測量 | 沒有執行回報該 commit 的覆蓋率。 |

分支趨勢僅包含完整的 commit。

## 效能影響 {#performance-impact}

插樁後的程式碼執行速度會稍慢。Tuist 僅對你儲存庫中的 crate 進行插樁：依賴項目的建構方式與一般建構完全相同，並繼續從快取中取得。Tuist 會在 target 目錄中保留你自己 crate 的兩種變體，因此在有無覆蓋率的執行之間切換時，除非程式碼有所變更，否則不會重新建構它們。

## 限制 {#limitations}

- **使用特定目標 `rustflags` 的自訂 `rustc-wrapper`。** 當你的專案設定自己的 `rustc-wrapper` 時，Tuist 會改為將 `-C instrument-coverage` 加入 Cargo 的 `build.rustflags`。Cargo 設定檔中的 `target.<triple>.rustflags` 項目會取代它們，因此請自行在該處加入旗標。若執行的測試未寫入任何覆蓋率資料，系統會指出這一點。
- **已設定的目標執行器。** Tuist 會透過自己的執行器啟動測試二元檔。Cargo 設定檔中的 `target.<triple>.runner` 會取代它：執行的覆蓋率仍會上傳，但 Tuist 無法得知哪個測試二元檔執行了哪些內容。透過 `CARGO_TARGET_<TRIPLE>_RUNNER` 環境變數設定的執行器則會繼續正常運作。
- **來自分叉的拉取請求不會提供覆蓋率。** 只有通過 Tuist 驗證的執行才會上傳覆蓋率，而 CI 通常會扣留來自分叉的拉取請求的秘密金鑰和身分識別令牌。

## 查詢覆蓋率 {#querying}

儀表板的 **程式碼覆蓋率** 頁面顯示每個 commit 的數值、其套件及其檔案，以及每個檔案所包含的函式。代理程式可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 存取相同的資料。
