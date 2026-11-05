---
{
  "title": "Rust 構建洞察",
  "titleTemplate": ":title · 構建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 中找出緩慢的 crate、比較構建效能，並檢查 Rust 編譯器的警告同錯誤。"
}
---
# Rust 建構洞察 {#rust-build-insights}

Build Insights 幫你找出拖慢 Cargo 建構的原因，並在全隊受影響之前捕捉 regressions。你可以比較本機建構與 CI，查看建構時間變化，並檢查每次建構中編譯的 crates。

> [!IMPORTANT] Requirements
> - 請依照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你的專案並進行驗證。

## 回報你的建構 {#report-your-builds}

透過 Tuist 執行你慣用的 Cargo 指令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo wrapper</.localized_link> 以繼續使用一般的 `cargo` 指令。你的參數、工具鏈選擇、輸出和退出碼都保持不變。

## 找出拖慢建構的原因 {#explore-your-builds}

在儀表板的 **Builds → Build Runs** 中開啟一個建構。使用日期、環境和 Rust 版本篩選器來比較相似的建構。建構及其快取計數也可透過 `tuist build cargo list` 和 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`，以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 取得。

在 **Overview** 中，使用 **Compiler jobs** 找出緩慢的 crates。依 **Duration** 或 **Started after**（自 Cargo 指令啟動後的時間）排序，或依 crate 名稱或根原始檔搜尋。

每一列代表對一個 crate 的一次 `rustc` 呼叫，該 crate 可能包含多個原始檔。**Crate root** 標示其根原始檔；持續時間是整個編譯器工作的時間，而非僅該檔案。一個 crate 可能因不同 target 或設定而出現多次。編譯器訊息歸類於 **Warnings** 和 **Errors**。

### 跨建構追蹤 crates {#crate-history}

對於已加入逐步推出 crate 歷史記錄功能的專案，**Builds → Crates** 會顯示觀察到的 crates 及其編譯歷史。開啟一個 crate 以比較其在各次建構中記錄的持續時間和結果，然後追溯到其 Cargo 建構。相同的清單也可透過專案 API 中的 `/cargo/crates` 以及帶有 `kind: cargo_crates` 的共用 MCP 建構實體工具取得。

Crates 按其精確記錄的根路徑、名稱和類型分組。更改 checkout 路徑可能會分割歷史記錄；不會區分 profiles、features 和 target triples。這是觀察到的編譯器工作清單，並非你工作區中的每個 crate。已快取或最新的 crates 不會產生編譯樣本。

### 歸屬建構報告 {#report-attribution}

經過驗證的報告可識別個人憑證背後的個人。共用憑證不一定需要識別個人。可選擇將 `TUIST_ACTOR_ID` 設定為回報機器上的穩定不透明識別碼；預設為關閉，並顯示為未經驗證的聲明，從不用於授權。較舊的伺服器可能會忽略此聲明。切勿在其中放入密鑰。

## 解讀時間數據 {#timing-boundaries}

建構持續時間是整個 Cargo 指令所花的時間。編譯器工作可以平行執行，因此它們的持續時間總和不等於建構持續時間。

Cargo 只會編譯需要重新建構的 crates。已經最新的 crates 不會出現在編譯器列表中。使用 Tuist 的編譯快取時，還原的工作會出現在快取測量中，而非作為編譯器執行。

Tuist 不會單獨測量 build scripts 或顯示建構時間軸。大型建構會顯示前 500 個編譯器工作，如果記錄了更多工作則會顯示通知。

## 解讀快取測量 {#cache-measurements}

`tuist cargo` 包含在 Tuist CLI 中實作的實驗性編譯快取。請參閱 <.localized_link href="/guides/features/cache/rust">Rust 快取指南</.localized_link> 以了解設定、透過 Kura 進行遠端讀寫、支援的編譯以及疑難排解。

開啟專案側邊欄中的 **Cargo Cache** 以追蹤各次建構的快取命中率以及記錄的傳輸、延遲和吞吐量測量。依日期或環境篩選，切換每日趨勢和單次建構命中率，或開啟最近的建構以檢查其快取活動。沒有快取測量的建構仍顯示為不可用，而非計為零。

開啟建構的 **Cache** 標籤頁以查看任務命中、任務未命中、命中率，以及下載和上傳的字節數。當建構報告快取數據時，此標籤頁會出現。

- **Cacheable Tasks** 顯示哪些編譯器和 build-script 任務複用了快取輸出。搜尋或篩選任務，檢查快取讀/寫延遲，並展開列以查看其輸出。
- **CAS Outputs** 顯示 artifact 的下載和上傳，包括其大小、持續時間和吞吐量。圖表計算已完成的傳輸；已存在的 artifact 和失敗的嘗試仍保留在表中。

**Hit** 表示複用了快取輸出。**Missed** 表示任務改為進行編譯。命中不分本地和遠端；CAS Outputs 顯示記錄的 artifact 操作。

如果詳細記錄缺失或不完整，頁面會顯示通知。摘要仍涵蓋整個建構。估計避免的編譯器工作 **並非節省的建筑耗時**。

> [!WARNING] Experimental compilation cache
> 快取處於實驗階段，並在 Apple silicon Mac 上通過驗證。函式庫根據編譯器讀取的原始碼進行快取；build scripts、procedural macros、可執行檔和原生代碼僅在 Apple silicon Mac 上快取。快取鍵將 checkout 和工具鏈路徑替換為佔位符，因此同一台機器上不同路徑的 checkout 會複用它們。增量編譯正常進行。

### 執行測試的建構 {#builds-that-run-tests}

`tuist cargo test` 報告整個指令的持續時間，包括其測試。它還透過 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> 報告個別測試結果，包括 doctests。個別測試結果顯示在 **Tests** 下；指令持續時間顯示在建構洞察中。

## 其他編譯器工具 {#other-compiler-tools}

Tuist 保留透過 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 設定配置的現有編譯器 wrapper，並保持 `RUSTC_WORKSPACE_WRAPPER` 不變。預先存在的全域 wrapper 會停用 Tuist 的快取和編譯器觀察器：Tuist 無法確定該 wrapper 是否實際執行了 rustc。自訂工作區 wrapper 同樣可能導致報告中的編譯器工作較少。

Tuist 透過 rustup 尋找 Cargo。如果你使用自訂安裝，請將 `TUIST_CARGO_EXECUTABLE` 設定為其可執行檔路徑。透過直接工具鏈路徑呼叫 Cargo 會繞過 mise 的 wrapper。Cargo alias 無法取代如 `build` 等內建指令。

如果你使用 Cargo 的 nightly `-C` 選項，請先切換到工作區：Tuist 會轉發 `-C` 指令，但不會收集它們的建構計時。

## 疑難排解 {#troubleshooting}

如果建構沒有出現在儀表板中，請啟用偵錯輸出以查看為何其報告未傳送：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

報告不會改變你的建構結果。
