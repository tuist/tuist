---
{
  "title": "Rust cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Reuse supported Rust compilation outputs locally and through Tuist's remote cache with Cargo."
}
---
# Rust 快取 {#rust-cache}

Tuist 會快取支援的 Rust 編譯輸出，讓 Cargo 在建構輸出被移除後可以重複使用。此快取內建於 Tuist CLI 中，無需安裝獨立的快取執行檔或 Cargo 外掛程式。

> [!WARNING] Experimental compilation cache
> 目前版本僅快取登錄檔葉節點程式庫：從 Cargo 登錄檔下載且不依賴其他 crate 的程式庫 crate。其他編譯則正常執行。由於快取鍵保留了絕對路徑與環境輸入，因此尚不支援在不同檢出位置之間重複使用。

## 啟用快取 {#enable-caching}

請依照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接您的專案並完成驗證。接著透過 Tuist 執行建構：

```sh
tuist cargo build --release
```

符合條件的編譯會自動進行快取，無需額外的快取設定或啟用旗標。Tuist 會根據您現有的專案與伺服器設定，探索帳戶的快取端點並取得快取憑證。

若您使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link> 以繼續輸入一般的 `cargo` 指令。

## 運作方式 {#how-it-works}

針對每個符合條件的編譯，Tuist 會：

1. 檢查本機快取中是否有相符的輸出。
2. 若本機未命中，則透過遠端執行 API（REAPI）查詢 Kura，下載任何缺少的內容，並在還原之前驗證輸出。
3. 若快取未命中，則正常執行編譯器。編譯成功後，會將輸出儲存於本機，並在獲得授權時透過 REAPI 上傳至 Kura。只有當所有參照的內容皆可用時，才會發布遠端快取項目。

本機與 CI 建構使用相同的遠端快取協定。讀寫存取權限來自 Tuist 伺服器發行的快取憑證以及您帳戶的 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可允許開發人員下載，同時將上傳限制為 CI 與帳戶權杖。快取寫入者為受信任的程式碼產生者：由於快取的編譯器輸出為可執行程式碼，因此請僅授予您信任的機器與權杖寫入權限。

若遠端設定失敗，本機快取仍可使用。無法使用、遺失或損毀的快取項目會退回至編譯。上傳失敗不會導致建構失敗，也不會捨棄其本機快取項目。

## 哪些內容可以被快取 {#what-can-be-cached}

目前的快取支援符合條件的登錄檔葉節點程式庫，這些程式庫會產生 Rust 程式庫產物及其附帶的中繼資料、相依性資訊，以及支援的分割除錯輸出。

以下項目仍會正常建構：

- 工作區 crate 與依賴其他 crate 的程式庫。
- 建構腳本、程序巨集，以及依賴其輸出的 crate。
- 可執行檔、測試二進位檔、原生連結，以及 C/C++ 編譯。
- 增量編譯、自訂目標，以及不受支援的編譯器引數或原始碼輸入。
- 僅含中繼資料的 `cargo check` 呼叫。
- 會發出呈現診斷訊息或非預期編譯器輸出的編譯。

既有的全域編譯器包裝器會停用 Tuist 的編譯快取與編譯器觀察器。自訂工作區包裝器也會略過快取。請參閱 <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具相容性</.localized_link>。

快取鍵包含套件內容、編譯器與工具鏈、引數、工作目錄及建構環境。憑證、Tuist 報告設定，以及已識別的 CI 執行中繼資料不會使項目失效。在編譯期間讀取那些排除變數的 crate 不會被快取。在測試重複使用時，請保持其他輸入及其絕對路徑一致。支援遠端傳輸並不代表輸出可以在不同檢出路徑之間重新定位。

## 驗證重複使用 {#verify-reuse}

Cargo 已經避免重新建構最新的輸出。若要測試 Tuist 的快取而非 Cargo 的現有輸出，請先建構一次，移除 Cargo 的輸出，然後重複相同的建構：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件的程式庫可在第二次建構時還原；不受支援的 crate 仍會編譯。移除 Cargo 的輸出並不會移除 Tuist 獨立的本機快取。此操作檢查的是重複使用，不一定是遠端下載：本機命中不需要從 Kura 傳輸。輸入驗證與快取操作會增加額外負擔，因此避免編譯並不保證小型 crate 的建構會更快。

## 檢查快取活動 {#inspect-cache-activity}

在專案儀表板中開啟 **Cargo Cache**，以檢查命中率、記錄的傳輸、延遲、吞吐量與最近的建構。開啟建構的 **Cache** 分頁，查看個別任務決策與 CAS 輸出。

缺少的測量值不會計為零，且快取命中不一定代表遠端下載。詳情請參閱 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用偵錯輸出以檢查快取傳輸與報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

若未看到任何命中，請確認您的建構包含符合條件的登錄檔葉節點程式庫、沒有其他編譯器包裝器優先生效，且編譯器、旗標、環境與路徑與填充快取的建構相符。對於遠端上傳，也請檢查驗證與帳戶的快取上傳政策。
