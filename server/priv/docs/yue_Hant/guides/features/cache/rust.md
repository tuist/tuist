---
{
  "title": "Rust 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Cargo，在本機及 Tuist 的遠端快取中重複使用受支援的 Rust 編譯輸出。"
}
---
# Rust 快取 {#rust-cache}

Tuist 會快取支援的 Rust 編譯輸出，讓 Cargo 在建構輸出被移除後可以重用。此快取已內建於 Tuist CLI，無需安裝獨立的快取執行檔或 Cargo 外掛。

> [!WARNING] Experimental compilation cache
> 目前版本只快取登錄檔葉節點程式庫：從 Cargo 登錄檔下載且不依賴其他 crate 的程式庫 crate。其他編譯會正常執行。快取金鑰會保留絕對路徑和環境輸入，因此尚未支援在不同檢出位置之間重用。

## 啟用快取 {#enable-caching}

按照<.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link>連接你的專案並進行驗證。然後透過 Tuist 執行建構：

```sh
tuist cargo build --release
```

符合條件的編譯會自動快取。無需額外的快取設定或啟用旗標。Tuist 會根據你現有的專案和伺服器設定，發現帳戶的快取端點並取得快取憑證。

如果你使用 mise，<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link>以繼續輸入一般的 `cargo` 指令。

## 運作方式 {#how-it-works}

對於每個符合條件的編譯，Tuist 會：

1. 檢查本機快取是否有相符的輸出。
2. 如果本機未命中，則透過遠端執行 API（REAPI）查詢 Kura，下載任何缺少的內容，並在還原之前驗證輸出。
3. 如果快取未命中，則正常執行編譯器。編譯成功後，它會將輸出儲存到本機，並在獲得授權時透過 REAPI 上傳到 Kura。只有當所有參照的內容都可用时，才會發布遠端快取項目。

本機和 CI 建構使用相同的遠端快取協定。讀寫權限來自 Tuist 伺服器發出的快取憑證以及你帳戶的<.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可以允許開發人員下載，同時將上傳限制為 CI 和帳戶權杖。快取寫入者是受信任的程式碼生產者：快取的編譯器輸出是可執行程式碼，因此只授予你信任的機器和權杖寫入權限。

如果遠端設定失敗，本機快取仍然可用。不可用、缺失或損壞的快取項目會回退到編譯。上傳失敗不會導致建構失敗，也不會丟棄其本機快取項目。

## 可以快取什麼 {#what-can-be-cached}

目前的快取支援產生 Rust 程式庫產物及其附帶中繼資料、相依性資訊和支援的分割偵錯輸出的合格登錄檔葉節點程式庫。

以下項目仍會正常建構：

- 工作區 crate 和依賴其他 crate 的程式庫。
- 建構腳本、過程巨集以及依賴其輸出的 crate。
- 可執行檔、測試二進位檔、原生連結和 C/C++ 編譯。
- 增量編譯、自訂目標，以及不支援的編譯器引數或來源輸入。
- 僅中繼資料的 `cargo check` 呼叫。
- 發出渲染診斷或意外編譯器輸出的編譯。

預先存在的全域編譯器包裝器會停用 Tuist 的編譯快取和編譯器觀察器。自訂工作區包裝器也會繞過快取。請參閱<.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具相容性</.localized_link>。

快取金鑰包括套件內容、編譯器和工具鏈、引數、工作目錄和建構環境。憑證、Tuist 報告設定和已識別的 CI 執行中繼資料不會使項目失效。在編譯期間讀取這些排除變數的 crate 不會被快取。在測試重用時，請保持其他輸入及其絕對路徑一致。遠端傳輸支援不會使輸出在不同檢出路徑之間可重新定位。

## 驗證重用 {#verify-reuse}

Cargo 已經避免重建最新的輸出。為了測試 Tuist 的快取而不是 Cargo 的現有輸出，請建構一次，移除 Cargo 的輸出，然後重複相同的建構：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件的程式庫可以在第二次建構時還原；不支援的 crate 仍會編譯。移除 Cargo 的輸出不會移除 Tuist 獨立的本機快取。這檢查的是重用，不一定是遠端下載：本機命中不需要從 Kura 傳輸。輸入驗證和快取操作會增加開銷，因此避免編譯並不保證小型 crate 的建構會更快。

## 檢查快取活動 {#inspect-cache-activity}

在專案儀表板中開啟**Cargo Cache**以檢查命中率、記錄的傳輸、延遲、吞吐量和最近的建構。開啟建構的**Cache**標籤以查看個別任務決策和 CAS 輸出。

缺失的測量值不會計為零，且快取命中不一定意味著遠端下載。詳情請參閱<.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用除錯輸出以檢查快取傳輸和報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

如果你沒有看到任何命中，請檢查你的建構是否包含合格的登錄檔葉節點程式庫，是否有其他編譯器包裝器佔用優先權，以及編譯器、旗標、環境和路徑是否與填充快取的建構相符。對於遠端上傳，還要檢查驗證和帳戶的快取上傳政策。
