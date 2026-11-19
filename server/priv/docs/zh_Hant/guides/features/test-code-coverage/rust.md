---
{
  "title": "Rust 程式碼涵蓋率",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳 Rust 專案中 Cargo 測試的程式行涵蓋率，並依檔案、套件和提交追蹤。"
}
---
# Rust 程式碼涵蓋率 {#rust-code-coverage}

程式碼涵蓋率會告訴你，你的測試執行了哪些程式碼行。Tuist 使用 LLVM 的原始碼基礎涵蓋率來測量每次 `cargo test` 執行的行涵蓋率，並將一個 commit 的所有執行合併為單一數值，分別針對專案、每個套件與每個檔案呈現。儀表板的 **程式碼涵蓋率** 頁面會以每個 commit 顯示，並呈現各分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 請依照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 進行設定
> - 你的 Rust 工具鏈中的 LLVM 工具（`llvm-tools`）。Tuist 會在由 rustup 管理的工具鏈上安裝這些工具。
> - 你的專案位於 Git 儲存庫中

## 設定 {#setup}

### 啟用涵蓋率 {#turn-coverage-on}

將以下內容加入工作區根目錄的 `Cargo.toml`：

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

涵蓋率仰賴 Tuist 在每次收集涵蓋率的執行時一併上傳的 Git 歷史紀錄，藉此將 commit 歸屬到其分支。在非 Git 儲存庫中進行的執行會上傳測試結果，但不會上傳涵蓋率。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/rust">將測試分片</.localized_link> 時，每個啟用涵蓋率的分片都會回報其自身目標的涵蓋率，而 Tuist 會將一次執行的所有分片合併為單一數值。分片刻意只執行測試套件的一部分，因此不會導致 commit 的涵蓋率不完整。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的涵蓋率通常來自多個工作：每個分片或每組功能各一個工作。Tuist 無法判斷最後一個工作何時已完成回報，因此需要你主動告知。當某個 commit 的所有測試工作都完成後，在一個依賴所有這些工作的工作中執行以下指令：

```sh
tuist cargo coverage-complete
```

該指令會從檢出目錄的 `HEAD` 讀取 commit，也就是你的測試所執行的 commit；若要指定其他 commit，請傳遞 `--commit <sha>`。在 commit 標記為完成之前，其涵蓋率會顯示為 **進行中**，且不會納入該分支的趨勢。

## 運作方式 {#how-it-works}

### Tuist 測量的內容 {#what-tuist-measures}

- **套件。** 每個 Cargo 套件在儀表板上都是一個目標，並擁有各自的涵蓋率。
- **僅產品程式碼。** 整合測試、基準測試與範例（`tests/`、`benches/` 與 `examples/` 目錄，以及這類型的目標）屬於測試程式碼。Tuist 會儲存它們，但不會將其納入任何數值計算。`#[cfg(test)]` 模組中的單元測試是其來源檔的一部分，因此其行數會與該檔案合併計算，如同 `cargo llvm-cov` 的行為。
- **函式。** 每一行程式碼都歸屬於在其上方最近開始的函式。泛型函式無論被具現化為多少種類型，都只計算一次。
- **文件測試** 會照常執行，但不會被測量。

Tuist 也會記錄每個測試二進位檔執行了哪些程式碼，以便日後進行基於涵蓋率的測試選擇。`cargo test` 會在單一程序中執行二進位檔的測試，因此該記錄屬於整個二進位檔，而非其個別測試。

### 略過的測試 {#skipped-tests}

當某次執行的參數排除了部分測試，例如測試名稱過濾、`--skip`、`--ignored`、`-p`、`--exclude`、`--lib` 或 `--test`，該 commit 的涵蓋率會標示為 **不完整**，除非另有另一次未排除任何測試的執行也已完成。若發生失敗導致 `cargo test` 在所有測試二進位檔執行前就停止，也會產生相同效果。請加上 `--no-fail-fast` 以繼續執行剩餘的二進位檔。

有些測試是刻意排除，不會讓 commit 變得不完整：

- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">隔離</.localized_link> 略過的測試。** 它們會被視為已移除，因此只有這些測試覆蓋的行會被計為未覆蓋。
- **其他分片的目標**，當你將測試分片時。
- **被忽略的測試**（`#[ignore]`），預設不會執行。

### 完整與不完整的 commit {#commit-status}

儀表板上的每個 commit 都有狀態：

| 狀態 | 說明 |
| --- | --- |
| 進行中 | 已有執行回報涵蓋率，但尚未針對該 commit 執行 `tuist cargo coverage-complete`。 |
| 完整 | 該 commit 所有執行的測試都已執行，或是被刻意排除。 |
| 不完整 | 部分涵蓋率無法判定，因此該數值為下限。 |
| 未測量 | 沒有任何執行回報此 commit 的涵蓋率。 |

分支的趨勢圖僅包含完整的 commit。

## 效能影響 {#performance-impact}

插樁後的程式碼執行速度會稍慢。Tuist 僅對你儲存庫中的 crate 進行插樁：相依套件會與一般建置完全相同地建置，並繼續從快取中取得。Tuist 會在 target 目錄中保留你自己 crate 的兩種變體，因此在有無涵蓋率的執行之間切換時，除非程式碼有所變更，否則不會重新建置它們。

## 限制 {#limitations}

- **使用目標專屬 `rustflags` 的自訂 `rustc-wrapper`。** 當你的專案設定自己的 `rustc-wrapper` 時，Tuist 會改為將 `-C instrument-coverage` 加入 Cargo 的 `build.rustflags`。Cargo 設定檔中的 `target.<triple>.rustflags` 項目會取代它們，因此請自行在該處加入旗標。若某次執行的測試未寫入任何涵蓋率，系統會明確指出。
- **已設定的目標執行器。** Tuist 會透過自身的執行器啟動測試二進位檔。Cargo 設定檔中的 `target.<triple>.runner` 會取而代之：執行的涵蓋率仍會上傳，但 Tuist 無法判斷哪個測試二進位檔執行了哪些內容。透過 `CARGO_TARGET_<TRIPLE>_RUNNER` 環境變數設定的執行器則能正常運作。
- **來自分叉的拉取請求不會提供涵蓋率。** 只有通過 Tuist 驗證的執行才會上傳涵蓋率，而 CI 通常會對來自分叉的拉取請求隱藏密鑰與身分令牌。

## 查詢涵蓋率 {#querying}

儀表板的 **程式碼涵蓋率** 頁面會顯示每個 commit 的數值、其套件與檔案，以及各檔案所包含的函式。代理程式也能透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 存取相同的資料。
