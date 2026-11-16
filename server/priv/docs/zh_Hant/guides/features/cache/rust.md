---
{
  "title": "Rust 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Cargo，在本地端以及 Tuist 的遠端快取中重複使用受支援的 Rust 編譯輸出。"
}
---
# Rust 快取 {#rust-cache}

Tuist 會快取支援的 Rust 編譯輸出，讓 Cargo 在建置輸出被移除後仍能重複使用。此快取內建於 Tuist CLI，無需安裝獨立的快取執行檔或 Cargo 外掛。

<!-- @snippet: ./_rust-experimental -->

## 啟用快取 {#enable-caching}

請依照<.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link>連接你的專案並完成驗證。接著透過 Tuist 執行建置：

```sh
tuist cargo build --release
```

符合條件的編譯會自動啟用快取，無需額外設定或啟用旗標。Tuist 會根據你現有的專案與伺服器設定，自動偵測帳戶的快取端點並取得快取憑證。

若你使用 mise，請<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link>，以便繼續輸入一般的 `cargo` 指令。

## 運作方式 {#how-it-works}

在 Cargo 啟動前，Tuist 會還原先前使用相同工具鏈、設定檔與組態所產生的登錄檔與 git 相依性輸出，讓 Cargo 認為這些輸出已是最新。Cargo 仍負責決定需要重新建置的內容。隨後，針對 Cargo 仍會執行的每個符合條件的編譯，Tuist 會：

1. 檢查本機快取中是否有相符的輸出。
2. 若本機未命中，則透過遠端執行 API（REAPI）向 Kura 查詢、下載缺少的內容，並在還原前驗證輸出。
3. 若發生快取未命中，則正常執行編譯器。編譯成功後，會將輸出儲存至本機，並在獲得授權時透過 REAPI 上傳至 Kura。只有當所有參照的內容都可取得時，才會發布遠端快取項目。

同一台機器上的建置會共用本機快取，包含其他工作樹或目標目錄中的建置。若另一個建置已在編譯相同的 crate 或執行相同的建置腳本，Tuist 會等待其完成並還原輸出，避免重複執行相同工作。若該建置耗時超過 10 分鐘，Tuist 將停止等待並自行編譯該 crate。

本機與 CI 建置使用相同的遠端快取協定。讀寫權限來自 Tuist 伺服器發放的快取憑證以及你帳戶的<.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可允許開發者下載，同時將上傳限制為 CI 與帳戶權杖。快取寫入者是受信任的程式碼產生者：由於快取的編譯器輸出是可執行程式碼，因此僅應將寫入權限授予你信任的機器與權杖。

若遠端設定失敗，本機快取仍可正常使用。無法取得、遺失或損毀的快取項目會退回至編譯。上傳失敗不會導致建置失敗，也不會捨棄其本機快取項目。

## 可快取的內容 {#what-can-be-cached}

快取支援：

- 函式庫 crate，包括工作區與路徑 crate、帶有相依性的 crate，以及具有產生原始碼的 crate。Tuist 會以編譯器讀取的原始碼作為鍵值。
- 在 Apple Silicon Mac 以及搭載 glibc 的 x86_64 與 arm64 Linux 上，對於無法事先透過原始碼檢查建立鍵值的編譯（例如使用程序巨集、內嵌組合語言或原生程式庫的 crate、程序巨集本身，以及連結後的執行檔），Tuist 會記錄每個項目讀取的檔案、環境變數與唯讀指令（例如 `git describe`），並以此建立鍵值。在 Linux 上，系統連結器、C 程式庫以及連結過程讀取的啟動檔案也會納入鍵值。
- 在相同平台上，建置腳本的執行（包括其所執行的 C 編譯；macOS 上使用預設的 Apple 編譯器，Linux 上使用任何動態連結的編譯器）也可被快取。只有在讀取的檔案、環境與指令均未變更時，才會還原該次執行。
- 警告與其他診斷訊息，這些會在快取的 crate 中再次顯示。

以下情況仍會正常建置：

- 在不含 glibc 的 Linux 發行版（例如 Alpine）上的建置腳本與已記錄的編譯。
- 會連線至網路、啟動 Tuist 無法觀察的程式（在 Linux 上為靜態連結程式），或在輸出目錄之外進行寫入的建置腳本。
- 增量編譯、自訂目標，以及不支援的編譯器引數或原始碼輸入。
- 僅含中繼資料的 `cargo check` 呼叫。
- 產生非預期編譯器輸出的編譯。
- 使用動態載入器設定（例如 `LD_PRELOAD`）執行，或使用位於 Rust 工具鏈與目標目錄之外的 `LD_LIBRARY_PATH` 目錄（例如從 shell 繼承，或位於目標目錄之外的 `build.build-dir`）執行的編譯。

既有的全域編譯器包裝器會停用 Tuist 的編譯快取與編譯器觀察器。自訂工作區包裝器也會略過快取。請參閱<.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具相容性</.localized_link>。

快取鍵值包含套件內容、編譯器與工具鏈、引數以及建置環境。檢出位置、目標目錄、Cargo home 與工具鏈位置會被替換為佔位符，因此不同路徑的檢出可以重複使用相同的項目。若 crate 的輸出內嵌了自身路徑（例如透過 `env!("CARGO_MANIFEST_DIR")`），則僅在該路徑下才能重複使用。憑證、Tuist 回報設定，以及已識別的 CI 執行中繼資料不會使項目失效。在編譯期間讀取這些排除變數的 crate 不會被快取。

## 驗證重複使用 {#verify-reuse}

Cargo 本來就會避免重新建置已是最新的輸出。若要測試 Tuist 的快取而非依賴 Cargo 的現有輸出，請先建置一次，移除 Cargo 的輸出，然後再次執行相同的建置：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件的函式庫可在第二次建置時還原；不支援的 crate 仍會編譯。移除 Cargo 的輸出並不會移除 Tuist 獨立的本機快取。此操作檢查的是重複使用，不一定是遠端下載：本機命中無需從 Kura 傳輸。輸入驗證與快取操作會帶來額外負擔，因此避免編譯並不保證小型 crate 的建置會更快。

若要檢查命中是否正確（例如在 CI 中作為金丝雀測試），可將任一變數設為 `sampled`（每 64 個 crate 中選一個，每次建置選擇相同的 crate）或 `always`：

- `TUIST_CARGO_VERIFY` 會檢查命中所使用的輸入是否仍為編譯器或建置腳本所讀取的內容。
- `TUIST_CARGO_VERIFY_RECOMPILE` 會重新編譯命中的項目，並將其輸出與快取中的輸出進行比較。

被檢查的 crate 會進行編譯而非還原，如同未快取一般，因此其輸出始終是最新的，且驗證不會改變建置結果。驗證絕不會儲存或替換被檢查 crate 的快取項目。若其最新輸出與快取中的不同，依賴它的 crate 將發生未命中，並像未快取的建置一樣被快取。遞增式編譯不可重現，因此對於這些情況，`TUIST_CARGO_VERIFY_RECOMPILE` 僅比較中繼資料與相依性資訊。使用 `TUIST_DEBUG=1` 時，每次檢查都會印出一行 `Tuist Cargo cache: verified`，而發現差異的檢查會被計入建置快取測量中的分歧。

## 檢查快取活動 {#inspect-cache-activity}

在專案儀表板中開啟 **Cargo Cache**，以檢查命中率、記錄的傳輸、延遲、吞吐量以及最近的建置。開啟建置的 **Cache** 分頁，查看個別任務決策與 CAS 輸出。

缺少的測量值不會計為零，且快取命中不一定代表遠端下載。詳情請參閱 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用除錯輸出以檢查快取傳輸與回報失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

除錯輸出也會說明為何編譯或建置腳本執行未被儲存。若未見任何命中，請確認沒有其他編譯器包裝器優先執行，且編譯器、旗標與環境與填充快取的建置相符。對於遠端上傳，也請檢查認證與帳戶的快取上傳政策。
