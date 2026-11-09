---
{
  "title": "Rust 建置洞察",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 中找出緩慢的 crate、比較建置效能，並檢視 Rust 編譯器的警告與錯誤。"
}
---
# Rust 建置洞察 {#rust-build-insights}

Build Insights 幫你找出拖慢 Cargo 建置的原因，並在影響整個團隊之前捕捉回歸問題。你可以比較本機建置與 CI，查看建置時間的變化，並檢查每次建置中編譯的 crate。

> [!IMPORTANT]
> **必要條件**
>
> - 按照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你的專案並進行驗證。

## 回報你的建置 {#report-your-builds}

透過 Tuist 執行你慣用的 Cargo 指令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link> 以繼續使用一般的 `cargo` 指令。你的參數、工具鏈選擇、輸出和退出碼都保持不變。

## 找出拖慢建置的原因 {#explore-your-builds}

在儀表板的 **Builds → Build Runs** 中開啟一個建置。使用日期、環境和 Rust 版本篩選器來比較相似的建置。你也可以透過 `tuist build cargo list` 和 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`，以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 取得建置及其快取計數。

在 **概覽** 中，使用 **編譯器工作** 找出緩慢的 crate。依 **持續時間** 或 **開始於之後**（自 Cargo 指令開始的時間）排序，或依 crate 名稱或根原始檔搜尋。

每一列代表對一個 crate 的一次 `rustc` 調用，該 crate 可能包含多個原始檔。**Crate 根目錄** 標示其根原始檔；持續時間是針對整個編譯器工作，而非僅該檔案。一個 crate 可能因不同的目標或設定而出現多次。編譯器訊息歸類於 **警告** 和 **錯誤**。

### 跨建置追蹤 crate {#crate-history}

當你的專案可用時，**Builds → Crates** 會顯示觀察到的 crate 及其編譯歷史記錄。開啟一個 crate 以比較其在不同建置中的記錄持續時間和結果，然後追蹤該編譯回到其 Cargo 建置。相同的清單也可透過專案 API 中的 `/cargo/crates` 以及帶有 `kind: cargo_crates` 的共用 MCP 建置實體工具取得。

Crate 按其確切記錄的根路徑、名稱和類型分組。變更檢出路徑可能會分割歷史記錄；設定檔、功能和目標三元組則不予區分。這是觀察到的編譯器工作清單，並非你工作區中的每個 crate。已快取或最新的 crate 不會產生編譯樣本。

### 歸屬建置報告 {#report-attribution}

經過驗證的報告會識別個人憑證背後的個人。共用憑證不一定需要識別個人。可選擇將 `TUIST_ACTOR_ID` 設定為回報機器上的穩定不透明識別碼；預設為關閉，並顯示為未經驗證的聲明，從不用於授權。較舊的伺服器可能會忽略此聲明。切勿在其中放入機密資料。

## 解讀時間數據 {#timing-boundaries}

建置持續時間是指整個 Cargo 指令所花費的時間。編譯器工作可以平行執行，因此它們的持續時間總和不等於建置持續時間。

Cargo 只會編譯需要重新建置的 crate。已經最新的 crate 不會出現在編譯器列表中。使用 Tuist 的編譯快取時，還原的工作會出現在快取測量中，而非作為編譯器執行。

Tuist 不會單獨測量建置腳本或顯示建置時間軸。大型建置會顯示前 500 個編譯器工作，如果記錄了更多工作則會發出通知。

## 解讀快取測量數據 {#cache-measurements}

`tuist cargo` 包含一個在 Tuist CLI 中實作的實驗性編譯快取。請參閱 <.localized_link href="/guides/features/cache/rust">Rust 快取指南</.localized_link> 以了解設定、透過 Kura 進行遠端讀寫、支援的編譯以及疑難排解。

在專案側邊欄中開啟 **Cargo Cache** 以追蹤跨建置的快取命中率以及記錄的傳輸、延遲和吞吐量測量數據。依日期或環境篩選，在每日趨勢和單次建置命中率之間切換，或開啟最近的建置以檢查其快取活動。沒有快取測量數據的建置仍顯示為不可用，而非計為零。

開啟建置的 **快取** 分頁以查看任務命中、任務未命中、命中率，以及下載和上傳的字節數。當建置報告快取數據時，此分頁才會出現。

- **可快取任務** 顯示哪些編譯器和建置腳本任務復用了快取輸出。搜尋或篩選任務，檢查快取讀/寫延遲，並展開一列以查看其輸出。
- **CAS 輸出** 顯示工件的下載和上傳，包括其大小、持續時間和吞吐量。圖表統計已完成的傳輸；已存在的工件和失敗的嘗試仍保留在表格中。

**命中** 表示復用了快取輸出。**未命中** 表示任務改為進行編譯。命中不分本地和遠端；CAS 輸出顯示記錄的工件操作。

如果詳細記錄缺失或不完整，頁面會顯示通知。摘要仍然涵蓋整個建置。估計避免的編譯器工作 **並非節省的实际建置時間**。

<!-- @snippet: ../cache/_rust-experimental -->

增量編譯正常進行。

### 執行測試的建置 {#builds-that-run-tests}

`tuist cargo test` 報告整個指令的持續時間，包括其測試。它也透過 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link> 報告個別測試結果，包括文件測試。個別測試結果顯示在 **測試** 下；指令持續時間顯示在建置洞察中。

## 其他編譯器工具 {#other-compiler-tools}

Tuist 保留透過 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 設定配置的現有編譯器包裝器，並保持 `RUSTC_WORKSPACE_WRAPPER` 不變。預先存在的全域包裝器會停用 Tuist 的快取和編譯器觀察器：Tuist 無法確定該包裝器是否實際執行了 rustc。自訂工作區包裝器同樣可能導致報告中的編譯器工作較少。

Tuist 透過 rustup 尋找 Cargo。如果你使用自訂安裝，請將 `TUIST_CARGO_EXECUTABLE` 設定為其可執行檔路徑。透過直接工具鏈路徑呼叫 Cargo 會繞過 mise 的包裝器。Cargo 別名無法取代內建指令，例如 `build`。

如果你使用 Cargo 的 nightly `-C` 選項，請先切換到工作區：Tuist 會轉發 `-C` 指令，但不會收集其建置時間數據。

## 疑難排解 {#troubleshooting}

如果建置未出現在儀表板中，請啟用除錯輸出以查看為何未發送其報告：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

報告不會改變你的建置結果。
