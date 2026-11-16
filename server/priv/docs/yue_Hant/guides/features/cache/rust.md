---
{
  "title": "Rust 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Cargo，在本地及 Tuist 遠端快取中重複使用受支援嘅 Rust 編譯輸出。"
}
---
# Rust 快取 {#rust-cache}

Tuist 會快取支援嘅 Rust 編譯輸出，令 Cargo 喺移除建構輸出之後可以重用佢哋。快取功能已內置於 Tuist CLI，無須安裝獨立嘅快取執行檔或 Cargo 外掛程式。

<!-- @snippet: ./_rust-experimental -->

## 啟用快取 {#enable-caching}

按照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你嘅專案並進行驗證。然後透過 Tuist 執行你嘅建構：

```sh
tuist cargo build --release
```

符合條件嘅編譯會自動快取。無須額外設定快取或使用啟用旗標。Tuist 會根據你現有嘅專案同伺服器設定，發現你帳戶嘅快取端點並取得快取憑證。

如果你使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link>，以便繼續輸入普通嘅 `cargo` 指令。

## 運作方式 {#how-it-works}

喺 Cargo 啟動之前，Tuist 會還原你嘅 registry 同 git 依賴項喺先前建構中產生嘅輸出（使用相同嘅工具鏈、設定檔同配置），令 Cargo 認為佢哋係最新。Cargo 仍然負責決定要重新建構乜嘢。然後，對於 Cargo 仍然執行嘅每個符合條件嘅編譯，Tuist 會：

1. 檢查其本地快取以尋找匹配嘅輸出。
2. 如果本機快取未命中，會透過 Remote Execution API (REAPI) 向 Kura 查詢、下載任何缺失的內容，並在還原之前驗證輸出。
3. 如果快取未命中，會正常執行編譯器。編譯成功後，會將輸出儲存至本機，並在獲得授權時透過 REAPI 上傳到 Kura。遠端快取項目只會在所有參照的內容都可用之後才會發布。

同一部機器上嘅建構會共用本地快取，包括其他工作樹或目標目錄中嘅建構。當另一個建構已經編譯緊相同嘅 crate 或運行緊相同嘅建構腳本時，Tuist 會等待佢完成並還原其輸出，避免重複執行相同工作。如果該建構耗時超過 10 分鐘，Tuist 會停止等待並自行編譯該 crate。

本地同 CI 建構使用相同嘅遠端快取協定。讀寫權限來自 Tuist 伺服器發出嘅快取憑證以及你帳戶嘅 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可以允許開發人員下載，同時限制只有 CI 同帳戶令牌可以先上傳。快取寫入者係受信任嘅代碼生產者：由於快取嘅編譯器輸出係可執行代碼，因此只應向你信任嘅機器同令牌授予寫入權限。

如果遠端設定失敗，本地快取仍然可用。無法使用、缺失或損壞嘅快取項目會回退到編譯。上傳失敗不會導致建構失敗，亦不會丟棄其本地快取項目。

## 可以快取乜嘢 {#what-can-be-cached}

快取支援：

- 函式庫 crates，包括 workspace 同路徑 crates、帶有依賴項嘅 crates，以及帶有生成源碼嘅 crates。Tuist 會根據編譯器讀取嘅源碼為佢哋建立索引鍵。
- 喺 Apple silicon Mac 上，對於源碼檢查無法預先建立索引鍵嘅編譯，例如使用程序宏、內聯組合語言或原生函式庫嘅 crates、程序宏本身，以及連結後嘅可執行檔。Tuist 會記錄每個項目讀取嘅檔案、環境變數同唯讀指令（例如 `git describe`），並根據呢啲資訊建立索引鍵。
- 喺 Apple silicon Mac 上，建構腳本運行，包括佢哋使用預設 Apple 編譯器執行嘅 C 編譯。只有當佢讀取嘅檔案、環境同指令保持不變時，運行才會被還原。
- 警告同其他診斷訊息，快取嘅 crate 會再次顯示呢啲訊息。

以下情況仍然正常建構：

- Linux 上嘅建構腳本同已記錄嘅編譯。
- 連接網絡、啟動 Tuist 無法觀察嘅程式，或喺其輸出目錄之外寫入嘅建構腳本。
- 增量編譯、自訂目標，以及不受支援嘅編譯器參數或源碼輸入。
- 僅元數據嘅 `cargo check` 調用。
- 產生意外編譯器輸出嘅編譯。
- 使用動態載入器設定（例如 `LD_PRELOAD`）運行嘅編譯，或者使用位於 Rust 工具鏈同目標目錄之外嘅 `LD_LIBRARY_PATH` 目錄（例如從你嘅 shell 繼承，或者位於目標目錄之外嘅 `build.build-dir`）。

預先存在嘅全域編譯器包裝器會停用 Tuist 嘅編譯快取同編譯器觀察器。自訂 workspace 包裝器亦會繞過快取。請參閱 <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具相容性</.localized_link>。

快取索引鍵包括套件內容、編譯器同工具鏈、參數，以及建構環境。檢出目錄、目標目錄、Cargo home 同工具鏈位置會被替換為預留位置，因此喺另一條路徑檢出時可以重用相同項目。如果 crate 嘅輸出嵌入咗自己嘅路徑（例如透過 `env!("CARGO_MANIFEST_DIR")`），則只會在該路徑重用。憑證、Tuist 報告設定，以及已識別嘅 CI 運行元數據不會使項目失效。喺編譯期間讀取呢啲排除變數嘅 crates 不會被快取。

## 驗證重用 {#verify-reuse}

Cargo 已經避免重新建構最新嘅輸出。為了測試 Tuist 嘅快取而非 Cargo 嘅現有輸出，請建構一次，移除 Cargo 嘅輸出，然後重複相同嘅建構：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件嘅函式庫可以喺第二次建構時還原；不受支援嘅 crates 仍然會編譯。移除 Cargo 嘅輸出並不會移除 Tuist 獨立嘅本地快取。呢個操作檢查重用情況，未必涉及遠端下載：本地命中無須從 Kura 傳輸。輸入驗證同快取操作會增加開銷，因此避免編譯並唔保證小型 crates 嘅建構會更快。

要檢查命中是否正確（例如作為 CI 中嘅金絲雀測試），請將任一變數設定為 `sampled`（每 64 個 crate 中有一個，每次建構相同嘅 crates）或 `always`：

- `TUIST_CARGO_VERIFY` 檢查命中所依據嘅輸入是否仍然係編譯器或建構腳本讀取嘅內容。
- `TUIST_CARGO_VERIFY_RECOMPILE` 會重新編譯命中項目，並將其輸出與快取嘅輸出進行比較。

被檢查嘅 crate 會進行編譯而非還原，就好似佢未被快取一樣，因此其輸出始終係最新嘅，而驗證過程不會改變建構結果。驗證永遠不會儲存或替換被檢查 crate 嘅快取項目。如果其最新輸出與快取嘅輸出不同，依賴佢嘅 crates 就會出現未命中，並像未快取建構一樣被快取。增量編譯唔具可重現性，因此對於呢啲情況，`TUIST_CARGO_VERIFY_RECOMPILE` 只會比較元數據同依賴資訊。使用 `TUIST_DEBUG=1` 時，每次檢查都會列印一行 `Tuist Cargo cache: verified`，而發現差異嘅檢查會被計入建構快取測量中嘅分歧數。

## 檢查快取活動 {#inspect-cache-activity}

喺你項目嘅儀表板中打開 **Cargo Cache**，以檢查命中率、記錄嘅傳輸、延遲、吞吐量同最近嘅建構。打開某個建構嘅 **Cache** 標籤頁，查看個別任務決策同 CAS 輸出。

缺失嘅測量數據不會被計為零，而且快取命中並唔一定代表遠端下載。詳情請參閱 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用除錯輸出以檢查快取傳輸同報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

除錯輸出亦會解釋點解某次編譯或建構腳本運行未被儲存。如果你睇唔到任何命中，請檢查是否另有編譯器包裝器佔用優先權，以及編譯器、旗標同環境是否與填充快取嘅建構相匹配。對於遠端上傳，亦請檢查認證同帳戶嘅快取上傳政策。
