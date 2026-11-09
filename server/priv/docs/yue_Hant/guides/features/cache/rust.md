---
{
  "title": "Rust 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Cargo 在本機及 Tuist 遠端快取中重複使用受支援嘅 Rust 編譯輸出。"
}
---
# Rust 快取 {#rust-cache}

Tuist 會快取支援的 Rust 編譯輸出，讓 Cargo 在移除其建置輸出後可以重用它們。快取功能內建於 Tuist CLI，無需安裝獨立的快取執行檔或 Cargo 外掛程式。

<!-- @snippet: ./_rust-experimental -->

## 啟用快取 {#enable-caching}

按照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你的專案並完成驗證。然後透過 Tuist 執行你的建置：

```sh
tuist cargo build --release
```

符合條件的編譯會自動使用快取，無需額外的快取設定或啟用旗標。Tuist 會根據你現有的專案與伺服器設定，發現你帳戶的快取端點並取得快取憑證。

如果你使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link>，以便繼續輸入一般的 `cargo` 指令。

## 運作方式 {#how-it-works}

在 Cargo 啟動之前，Tuist 會還原先前以相同工具鏈、設定檔與組態產生的註冊表及 git 相依套件輸出，讓 Cargo 認為它們是最新的。Cargo 仍負責決定需要重新建置的內容。接著，對於 Cargo 仍然執行的每個符合條件的編譯，Tuist 會：

1. 檢查本機快取是否有相符的輸出。
2. 若本機未命中，則透過 Remote Execution API（REAPI）查詢 Kura，下載任何缺少的內容，並在還原之前驗證輸出。
3. 若發生快取未命中，則正常執行編譯器。編譯成功後，它會將輸出儲存在本機，並在獲得授權時透過 REAPI 上傳至 Kura。遠端快取項目只會在所有參考的內容都可用時才會發布。

本機與 CI 建置使用相同的遠端快取協定。讀取與寫入權限來自 Tuist 伺服器發出的快取憑證以及你帳戶的 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可以允許開發人員下載，同時將上傳限制為 CI 與帳戶權杖。快取寫入者是受信任的程式碼產生者：快取的編譯器輸出是可執行程式碼，因此只應向你信任的機器與權杖授予寫入權限。

如果遠端設定失敗，本機快取仍然可用。無法使用、缺少或損毀的快取項目會退回至編譯。上傳失敗不會導致建置失敗，也不會捨棄其本機快取項目。

## 哪些內容可以被快取 {#what-can-be-cached}

快取支援：

- 函式庫 crate，包括工作區與路徑 crate、帶有相依套件的 crate，以及帶有產生原始碼的 crate。Tuist 會根據編譯器讀取的原始碼作為索引鍵。
- 在 Apple silicon Mac 上，對於來源檢查無法預先建立索引鍵的編譯，例如使用程序巨集、內嵌組合語言或原生程式庫的 crate、程序巨集本身，以及連結的可執行檔。Tuist 會記錄每個項目讀取的檔案、環境變數與唯讀指令（例如 `git describe`），並以它們作為索引鍵。
- 在 Apple silicon Mac 上，建置腳本執行，包括它們使用預設 Apple 編譯器進行的 C 編譯。只有在讀取的檔案、環境與指令未改變時，才會還原執行。
- 警告與其他診斷訊息，這些訊息會在快取的 crate 中再次顯示。

以下項目仍會正常建置：

- Linux 上的建置腳本與已記錄的編譯。
- 連線至網路、啟動 Tuist 無法觀察的程式，或在輸出目錄之外寫入的建置腳本。
- 增量編譯、自訂目標，以及不支援的編譯器引數或來源輸入。
- 僅限中繼資料的 `cargo check` 呼叫。
- 發出非預期編譯器輸出的編譯。

既有的全域編譯器包裝器會停用 Tuist 的編譯快取與編譯器觀察器。自訂工作區包裝器也會繞過快取。請參閱 <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具相容性</.localized_link>。

快取索引鍵包含套件內容、編譯器與工具鏈、引數，以及建置環境。檢出位置、目標目錄、Cargo home 與工具鏈位置會被替換為佔位符，因此在其他路徑的檢出可以重用相同的項目。如果 crate 的輸出嵌入其自身路徑（例如透過 `env!("CARGO_MANIFEST_DIR")`），則只在該路徑下重用。憑證、Tuist 報告設定，以及可識別的 CI 執行中繼資料不會使項目失效。在編譯期間讀取那些排除變數的 crate 不會被快取。

## 驗證重用 {#verify-reuse}

Cargo 已經避免重新建置最新的輸出。若要測試 Tuist 的快取而非 Cargo 的現有輸出，請建置一次，移除 Cargo 的輸出，然後重複相同的建置：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件的函式庫可以在第二次建置時還原；不支援的 crate 仍會編譯。移除 Cargo 的輸出並不會移除 Tuist 獨立的本機快取。這是在檢查重用，不一定涉及遠端下載：本機命中不需要從 Kura 傳輸。輸入驗證與快取操作會增加額外負擔，因此避免編譯並不保證小型 crate 的建置會更快。

## 檢查快取活動 {#inspect-cache-activity}

在你專案的儀表板中開啟 **Cargo Cache**，以檢查命中率、記錄的傳輸、延遲、吞吐量與最近的建置。開啟建置的 **Cache** 標籤頁，查看個別任務決策與 CAS 輸出。

缺少的測量值不會計為零，且快取命中不一定代表遠端下載。詳情請參閱 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用偵錯輸出以檢查快取傳輸與報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

偵錯輸出也會說明為何未儲存編譯或建置腳本執行。如果你沒有看到任何命中，請確認沒有其他編譯器包裝器優先生效，且編譯器、旗標與環境與填充快取的建置相符。對於遠端上傳，也請檢查驗證與帳戶的快取上傳政策。
