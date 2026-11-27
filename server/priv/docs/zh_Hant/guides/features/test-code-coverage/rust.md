---
{
  "title": "Rust 程式碼涵蓋率",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳 Rust 專案 Cargo 測試的行涵蓋率，並依檔案、套件和提交追蹤。"
}
---
# Rust 程式碼涵蓋率 {#rust-code-coverage}

程式碼涵蓋率告訴你測試執行了哪些程式碼行。Tuist 使用 LLVM 的原始碼基礎涵蓋率，測量每次 `cargo test` 執行的行涵蓋率，並將一個 commit 的所有執行結果合併為單一數值，適用於專案、每個套件與每個檔案。儀表板的 **程式碼涵蓋率** 頁面會顯示每個 commit 的數值，以及各分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 請遵循 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link>
> - 你的 Rust 工具鏈中的 LLVM 工具（`llvm-tools`）。Tuist 會在 rustup 管理的工具鏈上安裝這些工具。
> - 你的專案位於 Git 儲存庫中

## 設定 {#setup}

### 啟用涵蓋率 {#turn-coverage-on}

將以下内容加入工作區根目錄的 `Cargo.toml`：

```toml
[workspace.metadata.tuist.test_insights.coverage]
upload = true
```

如果你改在 `tuist.toml` 中設定 Tuist，請在其中加入 `[test_insights.coverage]` 並設定 `upload = true`。

接著照常執行測試：

```sh
tuist cargo test --workspace
```

Tuist 會使用 `-C instrument-coverage` 建置你儲存庫中的 crate、執行測試，並將涵蓋率連同該次執行的測試結果一起上傳。測試的輸出與結束碼不會改變。若要覆寫單次執行的設定，請設定 `TUIST_COVERAGE_UPLOAD=1` 或 `TUIST_COVERAGE_UPLOAD=0`。

涵蓋率仰賴 Tuist 在每次收集涵蓋率的執行中上傳的 Git 歷史記錄，藉此將 commit 歸入其分支。在非 Git 儲存庫中執行的執行會上傳測試結果，但不包含涵蓋率。若是從某個 commit 的檢出而非分支執行，則沒有分支，也不會將 commit 歸入任何分支；在 Tuist 無法識別的 CI 系統上，請使用 `TUIST_GIT_BRANCH` 指定分支名稱，如 <.localized_link href="/guides/features/test-insights/rust#continuous-integration">持續整合</.localized_link> 所述。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/rust">將測試分片</.localized_link> 時，每個開啟涵蓋率的分片都會回報其自身目標的涵蓋率，而 Tuist 會將一次執行的各分片合併為單一數值。分片刻意只執行套件的一部分，因此不會導致 commit 的涵蓋率不完整。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的涵蓋率通常來自多個工作：每個分片或每組功能各一個。Tuist 無法判斷最後一個工作何時已完成回報，因此需要你告知。當一個 commit 的所有測試工作都完成後，在依賴所有這些工作的另一個工作中執行以下指令：

```sh
tuist coverage complete
```

此指令會從檢出的 `HEAD` 讀取 commit，也就是你的測試所執行的 commit；若要指定其他 commit，請傳遞 `--commit <sha>`。在 commit 完成之前，其涵蓋率會顯示為 **進行中**，且不會納入該分支的趨勢。

## 運作方式 {#how-it-works}

### Tuist 測量的內容 {#what-tuist-measures}

- **套件。** 每個 Cargo 套件在儀表板上都是一個目標，並擁有各自的涵蓋率。
- **僅產品程式碼。** 整合測試、基準測試與範例（`tests/`、`benches/` 與 `examples/` 目錄，以及這類型的目標）屬於測試程式碼。Tuist 會儲存它們，但不將其納入任何數值計算。`#[cfg(test)]` 模組中的單元測試屬於其來源檔案的一部分，因此其行數會與該檔案一併計入，如同 `cargo llvm-cov`。
- **函式。** 每一行都歸屬於最靠近其上方開始的函式。泛型函式無論實例化為多少種類型，都只計一次。
- **文件測試**會照常執行，但不會被測量。

Tuist 也會記錄每個測試二元檔執行了哪些程式碼，以便日後進行基於涵蓋率的測試選擇。`cargo test` 會在單一程序中執行二元檔的測試，因此該記錄屬於整個二元檔，而非其個別測試。

### 跳過的測試 {#skipped-tests}

當執行的參數排除某些測試時，例如測試名稱篩選器、`--skip`、`--ignored`、`-p`、`--exclude`、`--lib` 或 `--test`，該 commit 的涵蓋率會標示為 **不完整**，除非另有未排除任何內容的同一 commit 執行也已完成。若在每個測試二元檔都執行之前就因失敗而停止 `cargo test`，也會產生相同效果。請加上 `--no-fail-fast` 以繼續執行剩餘的二元檔。

有些測試是刻意排除，不會導致 commit 不完整：

- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">隔離</.localized_link> 跳過的測試。** 它們會被視為已移除，因此僅由它們涵蓋的行數會算作未涵蓋。
- **其他分片的目標**，當你將測試分片時。
- **忽略的測試**（`#[ignore]`），預設不會執行。

### 未提交的變更 {#uncommitted-changes}

若從有未提交變更的追蹤檔案之檢出執行，所測量的程式碼並非該 commit 的內容，因此其涵蓋率不會計入該 commit。該次執行會發出警告並列出變更的檔案。CI 工作在來源旁邊寫入的檔案（例如建置輸出或涵蓋率報告），只要 Git 未追蹤，就不算作變更。若只有這類執行測量了某個 commit，其涵蓋率會標示為 **不完整**，而 `tuist coverage complete` 會說明原因。

### 完整與不完整的 commit {#commit-status}

儀表板上的每個 commit 都有狀態：

| 狀態 | 意義 |
| --- | --- |
| 進行中 | 已有執行回報涵蓋率，但尚未對該 commit 執行 `tuist coverage complete`。 |
| 完整 | 該 commit 所有執行的測試都已執行，或是刻意排除。 |
| 不完整 | 部分涵蓋率無法判定，因此該數值為下限。 |
| 未測量 | 沒有任何執行回報該 commit 的涵蓋率。 |

分支趨勢僅包含完整的 commit。

## 效能影響 {#performance-impact}

插樁後的程式碼執行速度會稍慢。Tuist 僅對你儲存庫中的 crate 進行插樁：相依性的建置方式與一般建置完全相同，並持續從快取取得。Tuist 會在目標目錄中保留你自己 crate 的兩種變體，因此在有無涵蓋率的執行之間切換時，除非程式碼變更，否則不會重新建置它們。

## 限制 {#limitations}

- **使用特定目標 `rustflags` 的自訂 `rustc-wrapper`。** 當你的專案設定自己的 `rustc-wrapper` 時，Tuist 會改為將 `-C instrument-coverage` 加入 Cargo 的 `build.rustflags`。Cargo 設定檔中的 `target.<triple>.rustflags` 項目會取代它們，因此請自行在該處加入旗標。若某次執行的測試未寫入任何涵蓋率資料，系統會予以提示。
- **已設定的目標執行器。** Tuist 會透過自身的執行器啟動測試二元檔。Cargo 設定檔中的 `target.<triple>.runner` 會取代它：執行的涵蓋率仍會上傳，但 Tuist 無法判斷哪個測試二元檔執行了哪些內容。透過 `CARGO_TARGET_<TRIPLE>_RUNNER` 環境變數設定的執行器則可正常運作。
- **來自分叉的拉取請求不會提供涵蓋率。** 只有通過 Tuist 驗證的執行才會上傳涵蓋率，而 CI 通常會對來自分叉的拉取請求隱藏密鑰與身分令牌。

## 查詢涵蓋率 {#querying}

儀表板的 **程式碼涵蓋率** 頁面顯示每個 commit 的數值、其套件與檔案，以及各檔案包含的函式。代理程式也可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 存取相同的資料。
