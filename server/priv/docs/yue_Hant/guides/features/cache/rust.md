---
{
  "title": "Rust 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Cargo，喺本地同 Tuist 遙距快取中重用受支援嘅 Rust 編譯輸出。"
}
---
# Rust 快取 {#rust-cache}

Tuist 會快取支援的 Rust 編譯輸出，讓 Cargo 在移除其建置輸出後可以重用。快取已內建於 Tuist CLI。無需安裝獨立的快取執行檔或 Cargo 外掛程式。

<!-- @snippet: ./_rust-experimental -->

## 啟用快取 {#enable-caching}

按照<.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link>連接你的專案並進行驗證。然後透過 Tuist 執行你的建置：

```sh
tuist cargo build --release
```

符合條件的編譯會自動快取。沒有額外的快取設定或啟用旗標。Tuist 會使用你現有的專案和伺服器設定，探索你帳戶的快取端點並取得快取憑證。

如果你使用 mise，<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link>以繼續輸入一般的 `cargo` 指令。

## 運作方式 {#how-it-works}

在 Cargo 啟動之前，Tuist 會還原你先前使用相同工具鏈、設定檔和設定所產生的 registry 和 git 相依項目的輸出，讓 Cargo 認為它們是最新的。Cargo 仍負責決定要重新建置什麼。然後，對於 Cargo 仍然執行的每個符合條件的編譯，Tuist 會：

1. 檢查其本機快取是否有相符的輸出。
2. 如果本機未命中，則透過遠端執行 API (REAPI) 查詢 Kura，下載任何缺少的內容，並在還原之前驗證輸出。
3. 如果快取未命中，則正常執行編譯器。編譯成功後，它會在本機儲存輸出，並在獲得授權時透過 REAPI 將它們上傳到 Kura。只有在其所有參考的內容都可用時，才會發布遠端快取項目。

本機和 CI 建置使用相同的遠端快取協定。讀取和寫入權限來自 Tuist 伺服器發出的快取憑證以及你帳戶的<.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可以允許開發人員下載，同時限制只有 CI 和帳戶權杖才能上傳。快取寫入者是受信任的程式碼產生者：快取的編譯器輸出是可執行程式碼，因此只授予你信任的機器和權杖寫入權限。

如果遠端設定失敗，本機快取仍然可用。不可用、缺少或損毀的快取項目會回退到編譯。上傳失敗不會導致建置失敗，也不會捨棄其本機快取項目。

## 可以快取什麼 {#what-can-be-cached}

快取支援：

- 程式庫 crate，包括工作區和路徑 crate、具有相依項目的 crate，以及具有產生原始碼的 crate。Tuist 會根據編譯器讀取的原始碼為它們建立索引鍵。
- 在 Apple silicon Mac 上，無法預先透過原始碼檢查建立索引鍵的編譯，例如使用程序巨集、內嵌組合語言或原生程式庫的 crate、程序巨集本身，以及連結的可執行檔。Tuist 會記錄每個項目讀取的檔案、環境變數和唯讀指令（例如 `git describe`），並根據這些內容建立索引鍵。
- 在 Apple silicon Mac 上，build-script 執行，包括它們使用預設 Apple 編譯器執行的 C 編譯。只有當它讀取的檔案、環境和指令未改變時，才會還原執行。
- 警告和其他診斷訊息，快取的 crate 會再次顯示這些訊息。

以下項目仍會正常建置：

- Linux 上的建置腳本和已記錄的編譯。
- 連線到網路、啟動 Tuist 無法觀察的程式，或在輸出目錄之外寫入的建置腳本。
- 增量編譯、自訂目標，以及不支援的編譯器引數或原始碼輸入。
- 僅限中繼資料的 `cargo check` 呼叫。
- 發出意外編譯器輸出的編譯。
- 使用動態載入器設定（例如 `LD_PRELOAD`）執行的編譯，或使用位於 Rust 工具鏈和目標目錄之外的 `LD_LIBRARY_PATH` 目錄執行的編譯，例如從你的 shell 繼承的目錄，或位於目標目錄之外的 `build.build-dir`。

預先存在的全域編譯器包裝器會停用 Tuist 的編譯快取和編譯器觀察器。自訂工作區包裝器也會繞過快取。請參閱<.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具相容性</.localized_link>。

快取索引鍵包括套件內容、編譯器和工具鏈、引數以及建置環境。檢出、目標目錄、Cargo home 和工具鏈位置會被替換為預留位置，因此在其他路徑的檢出會重用相同的項目。如果 crate 的輸出內嵌了其自身路徑（例如透過 `env!("CARGO_MANIFEST_DIR")`），則只在該路徑重用。憑證、Tuist 報告設定和已識別的 CI 執行中繼資料不會使項目失效。在編譯期間讀取這些排除變數的 crate 不會被快取。

## 驗證重用 {#verify-reuse}

Cargo 已經避免重新建置最新的輸出。為了測試 Tuist 的快取而非 Cargo 的現有輸出，請建置一次，移除 Cargo 的輸出，然後重複相同的建置：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件的程式庫可以在第二次建置時還原；不支援的 crate 仍會編譯。移除 Cargo 的輸出不會移除 Tuist 獨立的本機快取。這檢查的是重用，不一定是遠端下載：本機命中不需要從 Kura 傳輸。輸入驗證和快取操作會增加開銷，因此避免編譯並不保證小型 crate 的建置會更快。

## 檢查快取活動 {#inspect-cache-activity}

在你專案的儀表板中開啟**Cargo Cache**，以檢查命中率、記錄的傳輸、延遲、吞吐量和最近的建置。開啟建置的**Cache**分頁以查看個別任務決策和 CAS 輸出。

缺少的測量值不會計為零，且快取命中不一定代表遠端下載。詳情請參閱<.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用偵錯輸出以檢查快取傳輸和報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

偵錯輸出也會解釋為什麼編譯或 build-script 執行未被儲存。如果你看不到任何命中，請檢查是否有其他編譯器包裝器優先生效，以及編譯器、旗標和環境是否與填充快取的建置相符。對於遠端上傳，也請檢查驗證和帳戶的快取上傳政策。
