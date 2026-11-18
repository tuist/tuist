---
{
  "title": "Rust 程式碼涵蓋率",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳 Rust 專案 Cargo 測試的行列涵蓋率，並按檔案、套件和提交追蹤。"
}
---
# Rust 程式碼涵蓋率 {#rust-code-coverage}

程式碼涵蓋率會告訴你測試執行了程式碼中的哪些行。Tuist 使用 LLVM 的原始碼基礎涵蓋率，測量每次 `cargo test` 執行的行涵蓋率，並將一個提交的所有執行合併為單一數值，適用於專案、每個套件與每個檔案。儀表板的 **程式碼涵蓋率** 頁面會以每次提交顯示，並呈現各分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 請依照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 進行設定
> - 你的 Rust 工具鏈中的 LLVM 工具（`llvm-tools`）。Tuist 會在 rustup 管理的工具鏈上安裝這些工具。
> - 你的專案位於 Git 儲存庫中

## 設定 {#setup}

### 啟用涵蓋率 {#turn-coverage-on}

將以下內容加入儲存庫根目錄的 `tuist.toml`：

```toml
[test_insights.coverage]
upload = true
```

接著照常執行測試：

```sh
tuist cargo test --workspace
```

Tuist 會以 `-C instrument-coverage` 建置你儲存庫中的 crate、執行測試，並將涵蓋率與該次執行的測試結果一起上傳。測試的輸出與結束碼不會改變。若要覆寫單次執行的設定，請設定 `TUIST_COVERAGE_UPLOAD=1` 或 `TUIST_COVERAGE_UPLOAD=0`。

涵蓋率仰賴 Tuist 在每次收集涵蓋率的執行中上傳的 Git 歷史記錄，藉此將提交歸屬到其分支。在非 Git 儲存庫中進行的執行會上傳測試結果，但不會上傳涵蓋率。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/rust">將測試分片</.localized_link> 時，每個開啟涵蓋率的分片都會回報其自身目標的涵蓋率，而 Tuist 會將一次執行的所有分片合併為單一數值。分片刻意只執行測試套件的一部分，因此不會讓提交的涵蓋率變得不完整。

### 在 CI 上完成每次提交 {#complete-each-commit}

一次提交的涵蓋率通常來自多個工作：每個分片或每組功能各一個工作。Tuist 無法判斷最後一個工作何時已完成回報，因此需要你告知。當某次提交的所有測試工作都完成後，在一個相依於所有這些工作的工作中執行以下指令：

```sh
tuist cargo coverage-complete
```

此指令會從檢出的版本讀取提交，或從你的 CI 服務在拉取請求中回報的提交；若要指定其他提交，請傳入 `--commit <sha>`。在提交標記為完成之前，其涵蓋率會顯示為 **進行中**，且不會納入該分支的趨勢。

## 運作方式 {#how-it-works}

### Tuist 測量的內容 {#what-tuist-measures}

- **套件。** 每個 Cargo 套件在儀表板上都是一個目標，並擁有各自的涵蓋率。
- **僅產品程式碼。** 整合測試、基準測試與範例（`tests/`、`benches/` 與 `examples/` 目錄，以及這類型的目標）屬於測試程式碼。Tuist 會儲存它們，但不會將其納入任何數值計算。`#[cfg(test)]` 模組中的單元測試是其原始檔的一部分，因此這些行會與該檔案一併計入，如同 `cargo llvm-cov`。
- **函式。** 每一行都歸屬於在其上方最近開始的函式。泛型函式無論實作了多少種類型，都只計一次。
- **文件測試** 會照常執行，但不會被測量。

Tuist 也會記錄每個測試二進位檔執行了哪些程式碼，以便日後進行基於涵蓋率的測試選擇。`cargo test` 會在單一程序中執行二進位檔的測試，因此該記錄屬於整個二進位檔，而非其個別測試。

### 略過的測試 {#skipped-tests}

當執行的參數排除了某些測試時，例如測試名稱篩選器、`--skip`、`--ignored`、`-p`、`--exclude`、`--lib` 或 `--test`，該提交的涵蓋率會標示為 **不完整**，除非另有一次未排除任何內容的執行也已完成。若在每個測試二進位檔都執行之前就因失敗而中止 `cargo test`，也會產生相同效果。加入 `--no-fail-fast` 以繼續執行剩餘的二進位檔。

有些測試是刻意排除，不會導致提交變得不完整：

- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">隔離</.localized_link> 略過的測試。** 它們會像被移除一樣排除，因此只有這些測試覆蓋的行會被視為未覆蓋。
- **其他分片的目標**，當你將測試分片時。
- **忽略的測試**（`#[ignore]`），預設不會執行。

### 完整與不完整的提交 {#commit-status}

儀表板上的每次提交都有一个狀態：

| 狀態 | 說明 |
| --- | --- |
| 進行中 | 已有執行回報涵蓋率，但尚未對該提交執行 `tuist cargo coverage-complete`。 |
| 完整 | 該提交的所有執行中的測試都已執行，或是被刻意排除。 |
| 不完整 | 部分涵蓋率無法判定，因此該數值為下限。 |
| 未測量 | 沒有任何執行回報該提交的涵蓋率。 |

分支的趨勢僅包含完整的提交。

## 效能影響 {#performance-impact}

插樁後的程式碼執行速度會稍慢。Tuist 僅對你儲存庫中的 crate 進行插樁：相依性的建置方式與一般建置完全相同，並持續從快取中取得。Tuist 會在目標目錄中保留你自己 crate 的兩種變體，因此在有無涵蓋率的執行之間切換時，除非程式碼有所變更，否則不會重新建置它們。

## 限制 {#limitations}

- **使用特定目標 `rustflags` 的自訂 `rustc-wrapper`。** 當你的專案設定自己的 `rustc-wrapper` 時，Tuist 會改為將 `-C instrument-coverage` 加入 Cargo 的 `build.rustflags`。Cargo 設定檔中的 `target.<triple>.rustflags` 項目會取代它們，因此請自行在該處加入旗標。若某次執行的測試未寫入任何涵蓋率資料，系統會明確指出。
- **已設定的目標執行器。** Tuist 會透過自身的執行器啟動測試二進位檔。Cargo 設定檔中的 `target.<triple>.runner` 會取代它：執行的涵蓋率仍會上傳，但 Tuist 無法判斷哪個測試二進位檔執行了哪些內容。透過 `CARGO_TARGET_<TRIPLE>_RUNNER` 環境變數設定的執行器則能正常運作。
- **來自分叉儲存庫的拉取請求不會提供涵蓋率。** 只有通過 Tuist 驗證的執行才會上傳涵蓋率，而 CI 通常會對來自分叉儲存庫的拉取請求隱藏密鑰與身分識別令牌。

## 查詢涵蓋率 {#querying}

儀表板的 **程式碼涵蓋率** 頁面顯示每次提交的數值、其套件與檔案，以及每個檔案所包含的函式。代理程式也可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 存取相同的資料。
