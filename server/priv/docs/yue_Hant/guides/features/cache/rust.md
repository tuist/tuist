---
{
  "title": "Rust 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Cargo，在本地端及 Tuist 的遠端快取中重複使用受支援的 Rust 編譯輸出。"
}
---
# Rust 快取 {#rust-cache}

Tuist 會快取支援的 Rust 編譯輸出，讓 Cargo 在建構輸出被移除後可以重用。快取功能已內建於 Tuist CLI，無需安裝獨立的快取執行檔或 Cargo 外掛。

<!-- @snippet: ./_rust-experimental -->

## 啟用快取 {#enable-caching}

按照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你的專案並進行驗證。然後透過 Tuist 執行建構：

```sh
tuist cargo build --release
```

符合條件的編譯會自動啟用快取，無需額外設定快取或啟用旗標。Tuist 會根據你現有的專案與伺服器設定，自動發現帳戶的快取端點並取得快取憑證。

如果你使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link>，以便繼續輸入一般的 `cargo` 指令。

## 運作方式 {#how-it-works}

在 Cargo 啟動之前，Tuist 會還原先前使用相同工具鏈、設定檔與組態所產生的註冊表與 git 依賴項目的輸出，讓 Cargo 認為它們是最新的。Cargo 仍負責決定需要重新建構的內容。接著，對於 Cargo 仍會執行的每個符合條件的編譯，Tuist 會：

1. 檢查本機快取中是否有相符的輸出。
2. 若本機未命中，則透過 Remote Execution API (REAPI) 查詢 Kura，下載任何缺少的內容，並在還原前驗證輸出。
3. 若發生快取未命中，則正常執行編譯器。編譯成功後，它會將輸出儲存於本機，並在獲得授權時透過 REAPI 上傳至 Kura。只有當所有參考的內容都可用时，遠端快取項目才會發布。

同一台機器上的建構會共用本機快取，包括其他工作樹或目標目錄中的建構。當另一個建構已經在編譯相同的 crate 或執行相同的建構腳本時，Tuist 會等待它完成並還原其輸出，避免重複執行相同工作。如果該建構耗時超過 10 分鐘，Tuist 會停止等待並自行編譯該 crate。

本機與 CI 建構使用相同的遠端快取協定。讀寫權限來自 Tuist 伺服器發出的快取憑證以及你帳戶的 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可以允許開發人員下載，同時限制只有 CI 和帳戶令牌才能上傳。快取寫入者是受信任的程式碼產生者：由於快取的編譯器輸出是可執行程式碼，因此只應授予你信任的機器和令牌寫入權限。

如果遠端設定失敗，本機快取仍然可用。無法使用、缺失或損壞的快取項目會回退到編譯。上傳失敗不會導致建構失敗，也不會丟棄其本機快取項目。

## 哪些內容可以被快取 {#what-can-be-cached}

快取支援：

- 函式庫 crate，包括工作區和路徑 crate、帶有依賴項目的 crate，以及帶有產生原始碼的 crate。Tuist 會根據編譯器讀取的原始碼為它們建立索引鍵。
- 在 Apple silicon Mac 以及帶有 glibc 的 x86_64 和 arm64 Linux 上，對於原始碼檢查無法預先建立索引鍵的編譯（例如使用過程宏、內嵌組合語言或原生函式庫的 crate、過程宏本身，以及連結的可執行檔），Tuist 會記錄每個項目讀取的檔案、環境變數和唯讀指令（例如 `git describe`），並以此建立索引鍵。在 Linux 上，系統連結器、C 函式庫以及連結所讀取的啟動檔案都是索引鍵的一部分。
- 在相同平台上，建構腳本的執行（包括它們執行的 C 編譯；在 macOS 上使用預設的 Apple 編譯器，在 Linux 上使用任何動態連結的編譯器）。只有當讀取的檔案、環境和指令未改變時，執行才會被還原。
- 警告和其他診斷訊息，這些會在快取的 crate 中再次顯示。

以下情況仍會正常建構：

- 在沒有 glibc 的 Linux 發行版（例如 Alpine）上的建構腳本和記錄的編譯。
- 連接網路、啟動 Tuist 無法觀察的程式（在 Linux 上為靜態連結程式），或在輸出目錄之外寫入的建構腳本。
- 增量編譯、自訂目標，以及不受支援的編譯器參數或原始碼輸入。
- 僅限元數據的 `cargo check` 呼叫。
- 發出意外編譯器輸出的編譯。
- 使用動態載入器設定（例如 `LD_PRELOAD`）執行，或使用位於 Rust 工具鏈和目標目錄之外的 `LD_LIBRARY_PATH` 目錄（例如從 shell 繼承或位於目標目錄之外的 `build.build-dir`）執行的編譯。

既有的全域編譯器包裝器會停用 Tuist 的編譯快取和編譯器觀察器。自訂工作區包裝器也會繞過快取。請參閱 <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具相容性</.localized_link>。

快取索引鍵包括套件內容、編譯器和工具鏈、參數以及建構環境。檢出位置、目標目錄、Cargo home 和工具鏈位置會被替換為佔位符，因此不同路徑的檢出可以重用相同的項目。如果 crate 的輸出嵌入了自身路徑（例如透過 `env!("CARGO_MANIFEST_DIR")`），則只能在該路徑下重用。憑證、Tuist 報告設定和已識別的 CI 執行元數據不會使項目失效。在編譯期間讀取這些排除變數的 crate 不會被快取。

## 驗證重用 {#verify-reuse}

Cargo 已經避免重新建構最新的輸出。為了測試 Tuist 的快取而非 Cargo 的現有輸出，請先建構一次，移除 Cargo 的輸出，然後重複相同的建構：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件的函式庫可以在第二次建構時還原；不受支援的 crate 仍會編譯。移除 Cargo 的輸出不會移除 Tuist 獨立的本機快取。這檢查的是重用，不一定是遠端下載：本機命中不需要從 Kura 傳輸。輸入驗證和快取操作會增加開銷，因此避免編譯並不保證小型 crate 的建構會更快。

為了檢查命中是否正確（例如作為 CI 中的金絲雀測試），將任一變數設定為 `sampled`（每 64 個 crate 中選一個，每次建構都選相同的 crate）或 `always`：

- `TUIST_CARGO_VERIFY` 檢查命中所使用的輸入是否仍然是編譯器或建構腳本讀取的內容。
- `TUIST_CARGO_VERIFY_RECOMPILE` 會重新編譯命中的項目，並將它們的輸出與快取的輸出進行比較。

被檢查的 crate 會進行編譯而非還原，就像未快取一樣，因此其輸出始終是最新的，且驗證不會改變建構結果。驗證永遠不會儲存或替換被檢查 crate 的快取項目。如果其最新輸出與快取的輸出不同，依賴它的 crate 將會未命中，並像未快取建構一樣被快取。增量編譯不可重現，因此對於這些情況，`TUIST_CARGO_VERIFY_RECOMPILE` 僅比較元數據和依賴資訊。使用 `TUIST_DEBUG=1` 時，每次檢查都會列印一行 `Tuist Cargo cache: verified`，而發現差異的檢查會被計為建構快取測量中的分歧。

## 檢查快取活動 {#inspect-cache-activity}

開啟專案儀表板中的 **Cargo Cache** 以檢查命中率、記錄的傳輸、延遲、吞吐量以及最近的建構。開啟建構的 **Cache** 分頁以查看個別任務決策和 CAS 輸出。

缺失的測量值不會計為零，且快取命中不一定意味著遠端下載。詳情請參閱 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用除錯輸出以檢查快取傳輸和報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

除錯輸出也會解釋為何編譯或建構腳本執行未被儲存。如果沒有看到命中，請檢查是否有其他編譯器包裝器佔用優先權，以及編譯器、旗標和環境是否與填充快取的建構相符。對於遠端上傳，也請檢查認證和帳戶的快取上傳政策。
