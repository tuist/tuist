---
{
  "title": "Rust 嘅 Cargo 編譯快取",
  "titleTemplate": ":title · Cache · 功能 · Guides · Tuist",
  "description": "透過 Tuist 嘅 Cargo 編譯快取，喺 CI 同全新克隆項目中縮短 Rust 編譯時間；呢個快取會喺本地同遠端快取中重用編譯輸出。"
}
---
# Rust 嘅 Cargo 編譯快取 {#rust-cache}

Tuist 會快取支援嘅 Rust 編譯輸出，等 Cargo 喺編譯輸出被移除之後可以重用佢哋，例如喺 `cargo clean`、切換分支或者另一個 checkout 之後。你可能亦都見過呢個做法叫做 Cargo 編譯快取或者 Rust 編譯快取：佢透過重用之前編譯過嘅內容（包括你工作區入面增量編譯嘅 crate）嚟縮短 Rust 編譯時間。快取功能內置於 Tuist CLI，唔需要安裝獨立嘅快取執行檔或者 Cargo 插件。

<!-- @snippet: ./_rust-experimental -->

## 啟用快取 {#enable-caching}

跟住 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 去連接你嘅專案並完成認證。然後透過 Tuist 執行你嘅編譯：

```sh
tuist cargo build --release
```

符合條件嘅編譯會自動使用快取。唔需要額外嘅快取設定或者啟用旗標。Tuist 會根據你現有嘅專案同伺服器設定，發現你帳戶嘅快取端點並取得快取憑證。

如果你用 mise，可以 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link>，繼續輸入普通嘅 `cargo` 指令。

## 運作原理 {#how-it-works}

喺 Cargo 開始之前，Tuist 會還原你嘅 registry 同 git 依賴項由之前使用相同工具鏈、profile 同配置產生嘅輸出，令 Cargo 認為佢哋係最新。Cargo 仍然負責決定要重新編譯乜嘢。然後，對於 Cargo 仍然執行嘅每個符合條件嘅編譯，Tuist 會：

1. 檢查本地快取有冇匹配嘅輸出。
2. 如果本地快取未命中，就透過 Remote Execution API (REAPI) 查詢 Kura，下載任何缺失嘅內容，並喺還原之前驗證輸出。
3. 如果快取未命中，就執行編譯器。編譯成功後，佢會將輸出儲存喺本地，並於獲得授權時透過 REAPI 上傳到 Kura。只有當所有引用嘅內容都可用时，遠端快取條目才會發布。

喺 CI 環境，crate 喺目標目錄嘅首次編譯會唔進行增量編譯，因為 Cargo 1.99 及之後版本預設已經咁做：冇之前嘅 session 可以重用，CI 唔會編輯佢編譯過嘅內容，而且建立 session 會令那次編譯變慢同埋快取條目變大。Tuist 會記住目標目錄入面嘅 crate，所以保留目標目錄嘅 job 下次會增量編譯佢。本地編譯會按照 Cargo 要求進行增量編譯，所以全新編譯後嘅第一次編輯仍然快速。無論點樣，快取條目都會共享。

同一部機器上嘅編譯會共享本地快取，包括其他 worktree 或目標目錄入面嘅編譯。當另一個編譯已經緊係編譯同一個 crate 或者執行同一個 build script 時，Tuist 會等待佢完成並還原其輸出，而唔係重複做同樣嘅工作。如果該編譯超過 10 分鐘，Tuist 會停止等待並自行編譯該 crate。

本地同 CI 編譯使用相同嘅遠端快取協議。讀寫權限來自 Tuist 伺服器發出嘅快取憑證同你帳戶嘅 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>。帳戶可以允許開發人員下載，同時限制只有 CI 同帳戶 token 先可以上傳。快取寫入者係受信任嘅代碼生產者：因為快取嘅編譯器輸出係可執行代碼，所以只授予你信任嘅機器同 token 寫入權限。

如果遠端設定失敗，本地快取仍然可用。無法使用、缺失或者損壞嘅快取條目會回退到編譯。上傳失敗唔會導致編譯失敗，亦唔會丟棄其本地快取條目。

## 可以快取乜嘢 {#what-can-be-cached}

快取支援：

- Library crate，包括工作區同 path crate、有依賴項嘅 crate，以及有生成源碼嘅 crate。Tuist 會根據編譯器讀取嘅源碼為佢哋建立索引。
- `cargo check` 同 `cargo clippy`，佢哋只將 library 編譯成 metadata。佢哋嘅條目同編譯條目分開，所以 check 永遠唔會為 `cargo build` 提供 library。`cargo clippy` 用普通編譯器編譯嘅依賴項（例如工作區外面嘅 path crate）會重用 `cargo check` 嘅條目。
- 喺 Apple silicon Mac 同埋帶有 glibc 嘅 x86_64 同 arm64 Linux 上，對於源碼檢查無法預先建立索引嘅編譯（例如使用過程宏、內聯彙編或原生庫嘅 crate、過程宏本身，以及連結好嘅可執行檔），Tuist 會記錄每個項目讀取嘅檔案、環境變數同唯讀指令（例如 `git describe`），並根據佢哋建立索引。喺 Linux 上，系統連結器、C 庫同連結讀取嘅啟動檔案都係索引嘅一部分。
- 喺相同平台上，build-script 運行（包括佢哋執行嘅 C 編譯：macOS 上使用預設 Apple 編譯器，Linux 上使用任何動態連結編譯器）。只有當佢讀取嘅檔案、環境同指令冇改變時，運行才會被還原。
- 警告同其他診斷資訊，快取嘅 crate 會再次顯示佢哋，包括 Clippy 嘅 lints。

以下情況仍然正常編譯：

- 喺冇 glibc 嘅 Linux 發行版（例如 Alpine）上嘅 build script 同記錄咗嘅編譯。
- 連接網絡、啟動 Tuist 無法觀察嘅程式（喺 Linux 上係靜態連結程式），或者喺輸出目錄之外寫入嘅 build script。
- 自定義 target，以及不受支援嘅編譯器參數或源碼輸入。
- 過程宏同 build script 嘅 Clippy 編譯，以及啟用 `cargo` lint group 嘅 Clippy 運行（佢會透過 `cargo metadata` 讀取工作區嘅每個 manifest 同其 lockfile）。
- 產生意外編譯器輸出嘅編譯。
- 使用動態載入器設定（例如 `LD_PRELOAD`）運行嘅編譯，或者使用 `LD_LIBRARY_PATH` 目錄喺 Rust 工具鏈同目標目錄之外嘅編譯（例如從你嘅 shell 繼承，或者 `build.build-dir` 喺目標目錄之外）。

預先存在嘅全局編譯器包裝器會禁用 Tuist 嘅編譯快取同編譯器觀察器。除咗 Clippy 之外嘅自定義工作區包裝器亦會繞過快取。詳情請見 <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">編譯器工具相容性</.localized_link>。

快取索引鍵包括套件內容、編譯器同工具鏈、參數，以及構建環境。Clippy 項目亦取決於 Clippy 版本、`CLIPPY_ARGS`、`CLIPPY_CONF_DIR`、`CLIPPY_DISABLE_DOCS_LINKS` 中嘅 lint 參數、套件嘅 `Cargo.toml`，以及 Clippy 載入嘅 `clippy.toml` 或 `.clippy.toml`。checkout、target 目錄、Cargo home 同工具鏈位置會被替換為佔位符，所以喺另一條路徑 checkout 會重用相同項目。如果 crate 嘅輸出嵌入咗自己嘅路徑（例如透過 `env!("CARGO_MANIFEST_DIR")`），就只係喺該路徑重用。憑證、Tuist 報告設定，以及已識別嘅 CI 運行元數據唔會令項目失效。喺編譯期間讀取呢啲被排除變數嘅 crate 唔會被快取。

## 驗證重用 {#verify-reuse}

Cargo 已經避免重新構建最新嘅輸出。為咗測試 Tuist 嘅快取而唔係 Cargo 現有嘅輸出，請先構建一次，刪除 Cargo 嘅輸出，然後重複相同嘅構建：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合條件嘅庫可以喺第二次構建時還原；不受支援嘅 crate 仍然會編譯。刪除 Cargo 嘅輸出並唔會刪除 Tuist 獨立嘅本地快取。呢個檢查係驗證重用，並唔一定涉及遠程下載：本地命中唔需要從 Kura 傳輸。輸入驗證同快取操作會增加開銷，所以避免編譯並唔保證細小 crate 嘅構建會更快。

為咗檢查命中是否正確（例如作為 CI 中嘅金絲雀測試），將任一變數設定為 `sampled`（每 64 個 crate 中選一個，每次構建都係相同嘅 crate）或 `always`：

- `TUIST_CARGO_VERIFY` 檢查命中所用嘅輸入索引鍵，是否仍然係編譯器或 build script 讀取嘅嗰啲。
- `TUIST_CARGO_VERIFY_RECOMPILE` 會再次編譯命中項目，並將其輸出與快取嘅輸出進行比較。

被檢查嘅 crate 會進行編譯而唔係還原，就好似佢未被快取一樣，所以佢嘅輸出始終係最新嘅，而且驗證唔會改變構建結果。驗證永遠唔會儲存或替換被檢查 crate 嘅快取項目。如果佢嘅最新輸出與快取嘅不同，依賴佢嘅 crate 就會 miss，並像未快取構建那樣被快取。增量編譯唔可重現，所以對於呢啲情況，`TUIST_CARGO_VERIFY_RECOMPILE` 只比較元數據同依賴資訊。使用 `TUIST_DEBUG=1` 時，每次檢查都會打印一行 `Tuist Cargo cache: verified`，而發現差異嘅檢查會被計入構建快取測量中嘅分歧。

## 檢查快取活動 {#inspect-cache-activity}

喺你項目嘅儀表板中打開 **Cargo Cache**，以檢查命中率、記錄嘅傳輸、延遲、吞吐量同最近嘅構建。打開構建嘅 **Cache** 標籤頁，查看個別任務決策同 CAS 輸出。

缺失嘅測量值唔會計為零，而且快取命中並唔一定意味著遠程下載。詳情請見 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 快取測量</.localized_link>。

## 疑難排解 {#troubleshooting}

啟用除錯輸出以檢查快取傳輸同報告失敗：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

除錯輸出亦會解釋點解編譯或 build-script 運行未被儲存。如果你見到冇命中，請檢查是否有其他編譯器包裝器優先執行，以及編譯器、標誌同環境是否與填充快取嘅構建匹配。對於遠程上傳，亦請檢查認證同帳戶嘅快取上傳策略。
