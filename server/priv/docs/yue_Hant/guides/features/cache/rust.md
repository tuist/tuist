---
{
  "title": "Rust 嘅 Cargo 建構快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 Cargo 建構快取，喺 CI 同全新克隆專案入面縮短 Rust 編譯時間；呢個快取會喺本地同遠端快取重用編譯輸出。"
}
---
# Rust 嘅 Cargo 構建快取 {#rust-cache}

Tuist 會快取支援嘅 Rust 編譯輸出，令到 Cargo 喺其構建輸出被移除後（例如執行 `cargo clean`、切換分支，或者喺另一個 checkout 入面）可以重用佢哋。你可能會見到呢個功能被稱為 Cargo 構建快取或者 Rust 編譯快取：佢透過重用之前構建編譯過嘅內容（包括你工作空間中增量編譯嘅 crate）來縮短 Rust 編譯時間。呢個快取內置於 Tuist CLI 之中。唔需要安裝獨立嘅快取可執行文件或 Cargo 插件。

<!-- @snippet: ./_rust-experimental -->

## 啟用快取 {#enable-caching}

跟隨 <.localized_link href="/guides/get-started/rust-project">Rust 項目設置</.localized_link> 嚟連接你嘅項目並進行身份驗證。然後透過 Tuist 運行你嘅構建：

```sh
tuist cargo build --release
```

對於符合條件嘅編譯，快取係自動啟用嘅。唔需要額外嘅快取配置或啟用標誌。Tuist 會根據你現有嘅項目同伺服器配置，發現你帳戶嘅快取端點並獲取快取憑證。

如果你使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">配置 Cargo 包裝器</.localized_link> 以繼續輸入普通嘅 `cargo` 命令。

## 運作原理 {#how-it-works}

喺 Cargo 啟動之前，Tuist 會恢復你嘅 registry 同 git 依賴項由之前使用相同工具鏈、profile 同配置嘅構建所產生嘅輸出，令到 Cargo 發現佢哋係最新嘅。Cargo 仍然負責決定要重新構建乜嘢。然後，對於 Cargo 仍然運行嘅每個符合條件嘅編譯，Tuist 會：

1. 檢查其本地快取以尋找匹配嘅輸出。
2. 如果本地未命中，則透過 Remote Execution API (REAPI) 查詢 Kura，下載任何缺失嘅內容，並喺恢復之前驗證輸出。
3. 如果快取未命中，則運行編譯器。編譯成功後，佢會將輸出存儲喺本地，並喺獲得授權時透過 REAPI 將佢哋上傳到 Kura。只有當所有引用嘅內容都可用時，遠程快取條目才會發布。

喺 CI 上，crate 喺目標目錄中嘅首次編譯會唔進行增量編譯，因為 Cargo 1.99 及更高版本默認已經咁做：冇之前嘅会话可以重用，CI 唔會編輯佢編譯過嘅內容，而構建一個会话會令到該編譯變慢且其快取條目變大。Tuist 會記住目標目錄中嘅 crate，所以保留其目標目錄嘅 job 下次會增量編譯佢。本地構建會按照 Cargo 嘅要求進行增量編譯，所以全新構建後嘅第一次編輯仍然保持快速。無論點樣，快取條目都係共享嘅。

同一部機器上嘅構建會共享本地快取，包括其他 worktrees 或目標目錄中嘅構建。當另一個構建已經喺編譯相同嘅 crate 或運行相同嘅構建腳本時，Tuist 會等待佢並恢復其輸出，而唔係重複做相同嘅工作。如果該構建耗時超過 10 分鐘，Tuist 會停止等待並自行編譯該 crate。

本地同 CI 構建使用相同嘅遠程快取協議。讀取同寫入權限來自 Tuist 伺服器發出嘅快取憑證以及你帳戶嘅 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳策略</.localized_link>。帳戶可以允許開發人員下載，同時限制只有 CI 同帳戶令牌先可以上傳。快取寫入者係受信任嘅代碼生產者：快取嘅編譯器輸出係可執行代碼，所以只授予你信任嘅機器同令牌寫入權限。

如果遠程設置失敗，本地快取仍然可用。不可用、缺失或損壞嘅快取條目會回退到編譯。上傳失敗唔會導致構建失敗，亦唔會丟棄其本地快取條目。

## 可以快取乜嘢 {#what-can-be-cached}

快取支援：

- Library crate，包括工作空間同路徑 crate、帶有依賴項嘅 crate，以及帶有生成源代碼嘅 crate。Tuist 會根據編譯器讀取嘅源代碼為佢哋建立索引。
- `cargo check` 同 `cargo clippy`，佢哋只將庫編譯為元數據。佢哋嘅條目同構建嘅條目係分開嘅，所以 check 永遠唔會為 `cargo build` 提供庫。`cargo clippy` 使用普通編譯器編譯嘅依賴項（例如工作空間之外嘅路徑 crate）會重用 `cargo check` 嘅條目。
- 喺 Apple silicon Mac 以及帶有 glibc 嘅 x86_64 同 arm64 Linux 上，對於源代碼檢查無法預先建立索引嘅編譯（例如使用過程宏、內聯彙編或原生庫嘅 crate、過程宏本身，以及鏈接嘅可執行文件）。Tuist 會記錄每個編譯讀取嘅文件、環境變量同只讀命令（例如 `git describe`），並根據佢哋建立索引。喺 Linux 上，鏈接讀取嘅系統鏈接器、C 庫同啟動文件亦係其索引嘅一部分。
- 喺相同嘅平台上，構建腳本運行（包括佢哋執行嘅 C 編譯：macOS 上使用默認嘅 Apple 編譯器，Linux 上使用任何動態鏈接嘅編譯器）。只有當佢讀取嘅文件、環境同命令無變化時，運行才會被恢復。
- 警告同其他診斷信息，快取嘅 crate 會再次顯示佢哋，包括 Clippy 嘅 lint。

以下情況仍然正常構建：

- 喺冇 glibc 嘅 Linux 發行版（例如 Alpine）上嘅構建腳本同記錄嘅編譯。
- 連接網絡、啟動 Tuist 無法觀察嘅程序（喺 Linux 上係靜態鏈接程序），或者喺其輸出目錄之外寫入嘅構建腳本。
- 自定義目標，以及不受支援嘅編譯器參數或源輸入。
- 過程宏同構建腳本嘅 Clippy 編譯，以及啟用 `cargo` lint 組嘅 Clippy 運行（佢透過 `cargo metadata` 讀取工作空間嘅每個 manifest 同其 lockfile）。
- 發出意外編譯器輸出嘅編譯。
- 使用動態加載器設置（例如 `LD_PRELOAD`）運行嘅編譯，或者使用 Rust 工具鏈同目標目錄之外嘅 `LD_LIBRARY_PATH` 目錄（例如從你嘅 shell 繼承嘅目錄，或者目標目錄之外嘅 `build.build-dir`）運行嘅編譯。

預先存在嘅全局編譯器包裝器會禁用 Tuist 嘅編譯快取同編譯器觀察器。除咗 Clippy 之外嘅自定義工作空間包裝器亦會繞過快取。請參閱 <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具兼容性</.localized_link>。

快取索引鍵包括套件內容、編譯器同工具鏈、參數，以及構建環境。Clippy 條目亦取決於 Clippy 版本、`CLIPPY_ARGS`、`CLIPPY_CONF_DIR`、`CLIPPY_DISABLE_DOCS_LINKS` 中嘅 lint 參數、套件嘅 `Cargo.toml`，以及 Clippy 加載嘅 `clippy.toml` 或 `.clippy.toml`。檢出目錄、目標目錄、Cargo home 同工具鏈位置會被替換為佔位符，因此喺另一路徑檢出時會重用相同條目。如果 crate 嘅輸出嵌入咗自身路徑（例如透過 `env!("CARGO_MANIFEST_DIR")`），則只會喺該路徑重用。憑證、Tuist 報告設置，以及已識別嘅 CI 運行元數據唔會使條目失效。喺編譯期間讀取呢啲排除變量嘅 crate 唔會被快取。

## 驗證重用 {#verify-reuse}

Cargo 已經避免重新構建最新嘅輸出。為咗測試 Tuist 嘅快取而非 Cargo 現有嘅輸出，請構建一次，刪除 Cargo 嘅輸出，然後重複相同嘅構建：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件嘅庫可以喺第二次構建時恢復；不受支援嘅 crate 仍然會編譯。刪除 Cargo 嘅輸出並唔會刪除 Tuist 獨立嘅本地快取。這檢查嘅係重用，而唔一定係遠程下載：本地命中唔需要從 Kura 傳輸。輸入驗證同快取操作會增加開銷，因此避免編譯並唔保證細小 crate 嘅構建會更快。

為咗檢查命中是否正確（例如作為 CI 中嘅金絲雀測試），將任一變量設置為 `sampled`（每 64 個 crate 中有一個，每次構建都係相同嘅 crate）或 `always`：

- `TUIST_CARGO_VERIFY` 檢查命中所用嘅索引鍵輸入是否仍然係編譯器或構建腳本讀取嘅內容。
- `TUIST_CARGO_VERIFY_RECOMPILE` 會再次編譯命中項，並將其輸出與快取嘅輸出進行比較。

被檢查嘅 crate 會進行編譯而非恢復，就像佢未被快取一樣，因此其輸出始終係最新嘅，且驗證唔會改變構建結果。驗證永遠唔會存儲或替換被檢查 crate 嘅快取條目。如果其最新輸出與快取嘅輸出不同，依賴佢嘅 crate 將會 miss，並像未快取構建一樣被快取。增量編譯唔可重現，因此對於呢類情況，`TUIST_CARGO_VERIFY_RECOMPILE` 僅比較元數據同依賴信息。使用 `TUIST_DEBUG=1` 時，每次檢查都會打印一行 `Tuist Cargo cache: verified`，而發現差異嘅檢查會被計入構建快取測量中嘅分歧。

## 檢查快取活動 {#inspect-cache-activity}

喺你項目嘅儀表板中打開 **Cargo Cache**，以檢查命中率、記錄嘅傳輸、延遲、吞吐量同最近嘅構建。打開構建嘅 **Cache** 標籤頁，查看個別任務決策同 CAS 輸出。

缺失嘅測量值唔會計為零，快取命中亦唔一定意味著遠程下載。詳情請參閱 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用調試輸出以檢查快取傳輸同報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

調試輸出亦會解釋為何編譯或構建腳本運行未被存儲。如果你睇唔到任何命中，請檢查是否有其他編譯器包裝器優先執行，以及編譯器、標誌同環境是否與填充快取嘅構建匹配。對於遠程上傳，亦請檢查身份驗證同賬戶嘅快取上傳策略。
