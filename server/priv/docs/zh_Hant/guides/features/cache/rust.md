---
{
  "title": "Rust 的 Cargo 建置快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 的 Cargo 建置快取，在 CI 與全新克隆專案中縮短 Rust 編譯時間；此快取能在本機並透過遠端快取重複使用編譯產出。"
}
---
# Rust 的 Cargo 建置快取 {#rust-cache}

Tuist 會快取支援的 Rust 編譯輸出，讓 Cargo 在建置輸出被移除後（例如執行 `cargo clean`、切換分支，或在另一個檢出目錄中）可以重複使用。你也可能將此稱為 Cargo 建置快取或 Rust 編譯快取：它透過重複使用先前建置已編譯的內容（包括工作區中增量編譯的 crate）來縮短 Rust 編譯時間。此快取內建於 Tuist CLI 中，無需安裝獨立的快取執行檔或 Cargo 外掛程式。

<!-- @snippet: ./_rust-experimental -->

## 啟用快取 {#enable-caching}

依照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你的專案並進行驗證。接著透過 Tuist 執行建置：

```sh
tuist cargo build --release
```

符合條件的編譯會自動啟用快取。無需額外的快取設定或啟用旗標。Tuist 會根據你現有的專案與伺服器設定，發現帳戶的快取端點並取得快取憑證。

若你使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link>，以便繼續輸入一般的 `cargo` 指令。

## 運作方式 {#how-it-works}

在 Cargo 啟動前，Tuist 會還原先前使用相同工具鏈、設定檔與組態所產生的 registry 與 git 相依性輸出，讓 Cargo 認為它們是最新的。Cargo 仍負責決定要重新建置哪些項目。接著，針對 Cargo 仍會執行的每個符合條件的編譯，Tuist 會：

1. 檢查本機快取中是否有相符的輸出。
2. 若本機未命中，則透過遠端執行 API（REAPI）查詢 Kura，下載任何缺少的內容，並在還原前驗證輸出。
3. 若快取未命中，則執行編譯器。編譯成功後，會將輸出儲存至本機，並在獲得授權時透過 REAPI 上傳至 Kura。遠端快取項目僅在其所有參考內容皆可用時才會發布。

在 CI 上，crate 在目標目錄中的首次編譯會以非增量方式執行，這與 Cargo 1.99 及更新版本的預設行為一致：因為沒有可重複使用的先前工作階段，CI 不會編輯其編譯內容，且建立工作階段會讓該次編譯變慢並使快取項目變大。Tuist 會記住目標目錄中的 crate，因此保留目標目錄的工作在下一次會以增量方式編譯它。本機建置會依照 Cargo 的要求以增量方式編譯，因此在全新建置後的首次編輯仍能保持快速。無論哪種情況，快取項目都會共享。

同一台機器上的建置會共享本機快取，包括其他工作樹或目標目錄中的建置。當另一個建置已在編譯相同的 crate 或執行相同的建置腳本時，Tuist 會等待其完成並還原其輸出，避免重複執行相同工作。若該建置耗時超過 10 分鐘，Tuist 將停止等待並自行編譯該 crate。

本機與 CI 建置使用相同的遠端快取協定。讀取與寫入權限來自 Tuist 伺服器發出的快取憑證，以及你帳戶的 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可允許開發人員下載，同時限制僅 CI 與帳戶令牌能上傳。快取寫入者是受信任的程式碼產生者：由於快取的編譯器輸出是可執行程式碼，因此只應授予你信任的機器與令牌寫入權限。

若遠端設定失敗，本機快取仍可使用。無法使用、缺失或損毀的快取項目會退回至編譯。上傳失敗不會導致建置失敗，也不會丟棄其本機快取項目。

## 哪些項目可被快取 {#what-can-be-cached}

快取支援：

- 函式庫 crate，包括工作區與路徑 crate、具有相依性的 crate，以及具有產生來源的 crate。Tuist 會依據編譯器讀取的來源為其建立索引鍵。
- `cargo check` 與 `cargo clippy`，這兩者僅將函式庫編譯為中繼資料。它們的項目與建置項目分開，因此 check 永遠不會為 `cargo build` 提供函式庫。`cargo clippy` 使用一般編譯器編譯的相依性（例如工作區外的路徑 crate）會重複使用 `cargo check` 的項目。
- 在 Apple Silicon Mac 以及搭載 glibc 的 x86_64 與 arm64 Linux 上，對於無法事先透過來源檢查建立索引鍵的編譯（例如使用程序巨集、內嵌組合語言或原生函式庫的 crate、程序巨集本身，以及連結的可執行檔），Tuist 會記錄每個項目讀取的檔案、環境變數與唯讀指令（例如 `git describe`），並以此建立索引鍵。在 Linux 上，連結器讀取的系統連結器、C 函式庫與啟動檔案也是其索引鍵的一部分。
- 在相同平台上，建置腳本執行（包括其所執行的 C 編譯；在 macOS 上使用預設的 Apple 編譯器，在 Linux 上使用任何動態連結的編譯器）。僅當其讀取的檔案、環境與指令未改變時，才會還原執行。
- 警告與其他診斷訊息，快取的 crate 會再次顯示這些訊息，包括 Clippy 的 lint。

以下項目仍會正常建置：

- 在不含 glibc 的 Linux 發行版（例如 Alpine）上的建置腳本與已記錄的編譯。
- 會連線至網路、啟動 Tuist 無法觀察的程式（在 Linux 上為靜態連結程式），或在其輸出目錄之外寫入的建置腳本。
- 自訂目標，以及不支援的編譯器引數或來源輸入。
- 程序巨集與建置腳本的 Clippy 編譯，以及啟用 `cargo` lint 群組的 Clippy 執行（該群組會透過 `cargo metadata` 讀取工作區的每個 manifest 及其鎖定檔）。
- 產生意外編譯器輸出的編譯。
- 使用動態載入器設定（例如 `LD_PRELOAD`）執行，或使用位於 Rust 工具鏈與目標目錄之外的 `LD_LIBRARY_PATH` 目錄（例如從 shell 繼承，或 `build.build-dir` 位於目標目錄之外）的編譯。

既有的全域編譯器包裝器會停用 Tuist 的編譯快取與編譯器觀察器。除 Clippy 以外的自訂工作區包裝器也會略過快取。請參閱 <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具相容性</.localized_link>。

快取索引鍵包含套件內容、編譯器與工具鏈、引數，以及建置環境。Clippy 項目還取決於 Clippy 版本、`CLIPPY_ARGS`、`CLIPPY_CONF_DIR`、`CLIPPY_DISABLE_DOCS_LINKS` 中的 lint 引數、套件的 `Cargo.toml`，以及 Clippy 載入的 `clippy.toml` 或 `.clippy.toml`。檢出目錄、目標目錄、Cargo home 與工具鏈位置會以預留位置取代，因此位於其他路徑的檢出會重複使用相同的項目。若 crate 的輸出內嵌了其自身路徑（例如透過 `env!("CARGO_MANIFEST_DIR")`），則僅在該路徑下重複使用。憑證、Tuist 報告設定，以及已識別的 CI 執行中繼資料不會使項目失效。在編譯期間讀取這些排除變數的 crate 不會被快取。

## 驗證重複使用 {#verify-reuse}

Cargo 已避免重新建置最新的輸出。若要測試 Tuist 的快取而非 Cargo 的現有輸出，請先建置一次，移除 Cargo 的輸出，然後重複相同的建置：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件的函式庫可在第二次建置時還原；不支援的 crate 仍會編譯。移除 Cargo 的輸出並不會移除 Tuist 獨立的本機快取。此操作檢查的是重複使用，不一定是遠端下載：本機命中不需要從 Kura 傳輸。輸入驗證與快取操作會增加額外負擔，因此避免編譯並不保證能加快小型 crate 的建置速度。

若要檢查命中是否正確（例如作為 CI 中的金絲雀測試），請將任一變數設為 `sampled`（每 64 個 crate 中的一個，每次建置相同的 crate）或 `always`：

- `TUIST_CARGO_VERIFY` 會檢查命中所使用的輸入是否仍為編譯器或建置腳本所讀取的輸入。
- `TUIST_CARGO_VERIFY_RECOMPILE` 會再次編譯命中的項目，並將其輸出與快取中的輸出進行比較。

受檢查的 crate 會進行編譯而非還原，如同未快取一般，因此其輸出始終為最新，且驗證不會改變建置結果。驗證絕不會儲存或取代受檢查 crate 的快取項目。若其最新輸出與快取中的輸出不同，依賴它的 crate 將會錯過並像未快取建置一樣被快取。增量編譯不可重現，因此對於這些情況，`TUIST_CARGO_VERIFY_RECOMPILE` 僅比較中繼資料與相依性資訊。使用 `TUIST_DEBUG=1` 時，每次檢查都會列印一行 `Tuist Cargo cache: verified`，而發現差異的檢查會被計入建置快取測量中的分歧。

## 檢查快取活動 {#inspect-cache-activity}

開啟專案儀表板中的 **Cargo Cache**，以檢查命中率、記錄的傳輸、延遲、吞吐量與最近的建置。開啟建置的 **Cache** 標籤頁，以查看個別任務決策與 CAS 輸出。

遺漏的測量不會計為零，且快取命中不一定代表遠端下載。詳情請參閱 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用除錯輸出以檢查快取傳輸與報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

除錯輸出也會說明為何未儲存編譯或建置腳本執行。若未看到任何命中，請確認沒有其他編譯器包裝器優先執行，且編譯器、旗標與環境與填充快取的建置相符。對於遠端上傳，也請檢查驗證與帳戶的快取上傳政策。
