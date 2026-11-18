---
{
  "title": "Rust 嘅 Cargo 編譯快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 Cargo 編譯快取，喺 CI 同新克隆項目中縮短 Rust 編譯時間；呢個快取會喺本地同遠端快取之間重用編譯輸出。"
}
---
# Rust 嘅 Cargo 編譯快取 {#rust-cache}

Tuist 會快取支援嘅 Rust 編譯輸出，令 Cargo 喺移除編譯輸出後（例如執行 `cargo clean`、切換分支或另一個 checkout）可以重用。你可能會見到呢個功能稱為 Cargo 編譯快取或 Rust 編譯快取：佢透過重用先前編譯嘅內容（包括工作區內增量編譯嘅 crate）來縮短 Rust 編譯時間。快取功能已內置於 Tuist CLI，無需安裝獨立嘅快取執行檔或 Cargo 插件。

<!-- @snippet: ./_rust-experimental -->

## 啟用快取 {#enable-caching}

按照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你嘅專案並進行身份驗證。然後透過 Tuist 執行編譯：

```sh
tuist cargo build --release
```

符合條件嘅編譯會自動啟用快取。無需額外嘅快取設定或啟用標誌。Tuist 會根據你現有嘅專案同伺服器設定，發現帳戶嘅快取端點並取得快取憑證。

如果你使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link> 以繼續輸入普通嘅 `cargo` 指令。

## 運作原理 {#how-it-works}

喺 Cargo 啟動之前，Tuist 會還原由先前編譯產生、且使用相同工具鏈、配置檔同設定嘅 registry 和 git 依賴項輸出，令 Cargo 認為它們已是最新。Cargo 仍然負責決定需要重新編譯嘅內容。接著，對於 Cargo 仍然執行嘅每個符合條件嘅編譯，Tuist 會：

1. 檢查本地快取中是否有匹配嘅輸出。
2. 如果本地未命中，則透過 Remote Execution API (REAPI) 查詢 Kura，下載任何缺失嘅內容，並喺還原之前驗證輸出。
3. 如果快取未命中，則執行編譯器。編譯成功後，它會將輸出存儲喺本地，並喺獲得授權時透過 REAPI 上傳到 Kura。只有當所有引用嘅內容都可用時，遠程快取條目才會發布。

喺 CI 環境中，目標目錄中 crate 嘅首次編譯會唔進行增量編譯，因為 Cargo 1.99 及之後版本預設已經咁做：沒有早前嘅會話可以重用，CI 不會編輯其編譯內容，而建立會話會令該編譯變慢並增大快取條目。Tuist 會記住目標目錄中嘅 crate，因此保留目標目錄嘅作業下次會進行增量編譯。本地編譯會按 Cargo 要求進行增量編譯，所以全新編譯後嘅首次編輯仍然快速。無論哪種方式，快取條目都會共享。

同一部機器上嘅編譯會共享本地快取，包括其他 worktrees 或目標目錄中嘅編譯。當另一個編譯已經在編譯同一個 crate 或運行同一個 build script 時，Tuist 會等待它並還原其輸出，避免重複工作。如果該編譯超過 10 分鐘，Tuist 會停止等待並自行編譯該 crate。

本地和 CI 編譯使用相同嘅遠程快取協議。讀寫權限來自 Tuist 伺服器發出嘅快取憑證和你帳戶嘅 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可以允許開發人員下載，同時限制只有 CI 和帳戶令牌才能上傳。快取寫入者是受信任嘅代碼生產者：由於快取嘅編譯器輸出是可執行代碼，因此只應向你信任嘅機器和令牌授予寫入權限。

如果遠程設定失敗，本地快取仍然可用。不可用、缺失或損壞嘅快取條目會回退到編譯。上傳失敗不會導致編譯失敗，亦不會丟棄其本地快取條目。

## 可以快取嘅內容 {#what-can-be-cached}

快取支援：

- 庫 crate，包括工作區和路徑 crate、帶有依賴項嘅 crate，以及帶有生成源代碼嘅 crate。Tuist 根據編譯器讀取嘅源代碼為它們建立索引。
- `cargo check` 和 `cargo clippy`，它們只將庫編譯為元數據。它們嘅條目與編譯條目分開，因此 check 永遠不會為 `cargo build` 提供庫。`cargo clippy` 使用普通編譯器編譯嘅依賴項（例如工作區外嘅路徑 crate）會重用 `cargo check` 嘅條目。
- 喺 Apple silicon Mac 以及帶有 glibc 嘅 x86_64 和 arm64 Linux 上，對於源代碼檢查無法預先建立索引嘅編譯（例如使用過程宏、內聯彙編或原生庫嘅 crate、過程宏本身，以及鏈接後嘅可執行文件）。Tuist 會記錄每個項目讀取嘅文件、環境變量和只讀命令（例如 `git describe`），並根據這些內容建立索引。喺 Linux 上，鏈接讀取嘅系統鏈接器、C 庫和啟動文件亦係索引嘅一部分。
- 喺相同平台上，build-script 運行，包括它們執行嘅 C 編譯（macOS 上使用默認 Apple 編譯器，Linux 上使用任何動態鏈接編譯器）。只有當讀取嘅文件、環境和命令未改變時，運行才會被還原。
- 警告和其他診斷信息，快取嘅 crate 會再次顯示這些信息，包括 Clippy 嘅 lints。

以下情況仍會正常編譯：

- 喺沒有 glibc 嘅 Linux 發行版（例如 Alpine）上嘅 build scripts 和記錄嘅編譯。
- 連接網絡、啟動 Tuist 無法觀察嘅程序（喺 Linux 上為靜態鏈接程序），或喺輸出目錄之外寫入嘅 build scripts。
- 自定義目標，以及不受支援嘅編譯器參數或源輸入。
- 過程宏和 build scripts 嘅 Clippy 編譯，以及啟用 `cargo` lint 組嘅 Clippy 運行，該組會透過 `cargo metadata` 讀取工作區嘅每個 manifest 及其 lockfile。
- 產生意外編譯器輸出嘅編譯。
- 使用動態加載器設置（例如 `LD_PRELOAD`）運行嘅編譯，或使用位於 Rust 工具鏈和目標目錄之外嘅 `LD_LIBRARY_PATH` 目錄（例如從 shell 繼承或位於目標目錄之外嘅 `build.build-dir`）運行嘅編譯。

預先存在嘅全局編譯器包裝器會禁用 Tuist 嘅編譯快取和編譯器觀察器。除 Clippy 之外嘅自定義工作區包裝器亦會繞過快取。請參閱 <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具兼容性</.localized_link>。

快取索引鍵包括套件內容、編譯器和工具鏈、參數，以及構建環境。Clippy 條目亦取決於 Clippy 版本、`CLIPPY_ARGS`、`CLIPPY_CONF_DIR`、`CLIPPY_DISABLE_DOCS_LINKS` 中的 lint 參數、套件的 `Cargo.toml`，以及 Clippy 加載的 `clippy.toml` 或 `.clippy.toml`。檢出目錄、目標目錄、Cargo home 和工具鏈位置會被替換為佔位符，因此位於其他路徑的檢出會重用相同的條目。如果 crate 的輸出嵌入了其自身路徑（例如透過 `env!("CARGO_MANIFEST_DIR")`），則僅在該路徑下重用。憑證、Tuist 報告設置和已識別的 CI 運行元數據不會使條目失效。在編譯期間讀取這些排除變量的 crate 不會被快取。

## 驗證重用 {#verify-reuse}

Cargo 已經避免重新構建最新的輸出。為了測試 Tuist 的快取而非 Cargo 的現有輸出，請先構建一次，刪除 Cargo 的輸出，然後重複相同的構建：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件的庫可以在第二次構建時還原；不受支援的 crate 仍會編譯。刪除 Cargo 的輸出並不會刪除 Tuist 獨立的本地快取。這檢查的是重用，不一定是遠程下載：本地命中不需要從 Kura 傳輸。輸入驗證和快取操作會增加開銷，因此避免編譯並不保證小型 crate 的構建更快。

要檢查命中是否正確（例如作為 CI 中的金絲雀測試），請將任一變量設置為 `sampled`（每 64 個 crate 中選一個，每次構建相同的 crate）或 `always`：

- `TUIST_CARGO_VERIFY` 檢查命中所使用的輸入是否仍然是編譯器或 build script 讀取的輸入。
- `TUIST_CARGO_VERIFY_RECOMPILE` 會再次編譯命中的項目，並將其輸出與快取中的輸出進行比較。

被檢查的 crate 會進行編譯而不是還原，就像它未被快取一樣，因此其輸出始終是最新的，且驗證不會改變構建結果。驗證從不存儲或替換被檢查 crate 的快取條目。如果其最新輸出與快取中的不同，依賴它的 crate 將會miss，並像未快取構建一樣被快取。增量編譯不可復現，因此對於這些情況，`TUIST_CARGO_VERIFY_RECOMPILE` 僅比較元數據和依賴信息。使用 `TUIST_DEBUG=1` 時，每次檢查都會打印一行 `Tuist Cargo cache: verified`，而發現差異的檢查會在構建的快取測量中被計為分歧。

## 檢查快取活動 {#inspect-cache-activity}

在項目的儀表板中打開 **Cargo Cache**，以檢查命中率、記錄的傳輸、延遲、吞吐量和最近的構建。打開構建的 **Cache** 標籤頁，查看單個任務決策和 CAS 輸出。

缺失的測量值不會計為零，且快取命中不一定意味著遠程下載。詳情請參閱 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用調試輸出以檢查快取傳輸和報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

調試輸出還會解釋為何編譯或 build-script 運行未被存儲。如果沒有看到命中，請檢查是否有其他編譯器包裝器佔用優先級，以及編譯器、標誌和環境是否與填充快取的構建匹配。對於遠程上傳，還請檢查身份驗證和賬戶的快取上傳策略。
