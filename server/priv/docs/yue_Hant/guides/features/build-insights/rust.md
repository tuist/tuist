---
{
  "title": "Rust 構建分析",
  "titleTemplate": ":title · 構建分析 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 中找出緩慢的 crate、比較構建效能，並檢查 Rust 編譯器的警告與錯誤。"
}
---
# Rust 建構洞察 {#rust-build-insights}

Build Insights 幫你找出拖慢 Cargo 建構的因素，並在影響整個團隊之前捕捉 regressions。你可以比較本機建構與 CI，查看建構時間的變化，並檢查每次建構中編譯的 crates。

> [!IMPORTANT]
> **要求**
>
> - 按照<.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link>連接你的專案並進行驗證。

## 匯報你的建構 {#report-your-builds}

透過 Tuist 執行你慣用的 Cargo 指令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，請<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo wrapper</.localized_link>以繼續使用一般的 `cargo` 指令。你的參數、工具鏈選擇、輸出和退出碼保持不變。

## 找出拖慢建構的因素 {#explore-your-builds}

在儀表板的**Builds → Build Runs**中開啟一個建構。使用日期、環境和 Rust 版本篩選器來比較相似的建構。你也可以透過 `tuist build cargo list` 和 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`，以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 取得建構及其快取計數。

在**概覽**中，使用**編譯器工作**找出緩慢的 crate。依**持續時間**或**開始於之後**（自 Cargo 指令開始的時間）排序，或依 crate 名稱或根原始檔搜尋。

每一列代表對一個 crate 的一次 `rustc` 呼叫，該 crate 可能包含多個原始檔。**Crate root** 標示其根原始檔；持續時間是針對整個編譯器工作，而非僅該檔案。同一個 crate 可能因不同的 target 或設定而出現多次。編譯器訊息歸類在**警告**和**錯誤**中。

### 跨建構追蹤 crates {#crate-history}

當你的專案可用時，**Builds → Crates** 會顯示觀察到的 crates 及其編譯歷史記錄。開啟一個 crate 以比較其在不同建構中的記錄持續時間和結果，然後追溯該編譯回到其 Cargo 建構。相同的清單也可透過專案 API 中的 `/cargo/crates` 以及帶有 `kind: cargo_crates` 的共用 MCP 建構實體工具取得。

Crates 按其精確記錄的根路徑、名稱和類型分組。更改 checkout 路徑可能會分割歷史記錄；profiles、features 和 target triples 不會被區分。這是觀察到的編譯器工作的清單，並非你工作區中的所有 crate。已快取或已是最新的 crates 不會產生編譯樣本。

### 歸屬建構報告 {#report-attribution}

經過驗證的報告會識別個人憑證背後的個人。共用憑證無需識別個人。可選地在報告機器上將 `TUIST_ACTOR_ID` 設定為穩定的不透明識別碼；預設為關閉，並顯示為未經聲明的主張，從不用於授權。較舊的伺服器可能會忽略該主張。請勿在其中放置秘密。

## 解讀時間數據 {#timing-boundaries}

建構持續時間是指整個 Cargo 指令所花的時間。編譯器工作可以平行執行，因此它們的持續時間總和不等於建構持續時間。

Cargo 只會編譯需要重新建構的 crates。已經是最新的 crates 不會出現在編譯器列表中。使用 Tuist 的編譯快取時，還原的工作會出現在快取測量中，而非作為編譯器執行。

Tuist 不會單獨測量 build scripts 或顯示建構時間軸。大型建構會顯示前 500 個編譯器工作，如果記錄了更多則會顯示通知。

## 解讀快取測量 {#cache-measurements}

`tuist cargo` 包含在 Tuist CLI 中實作的實驗性編譯快取。請參閱<.localized_link href="/guides/features/cache/rust">Rust 快取指南</.localized_link>以了解設定、透過 Kura 進行的遠端讀寫、支援的編譯以及疑難排解。

在專案側邊欄中開啟**Cargo Cache**，以追蹤跨建構的快取命中率以及記錄的傳輸、延遲和吞吐量測量。依日期或環境篩選，在每日趨勢和個別建構命中率之間切換，或開啟最近的建構以檢查其快取活動。沒有快取測量的建構仍顯示為不可用，而非計為零。

開啟建構的**快取**標籤頁，查看工作命中、工作未命中、命中率，以及下載和上傳的字節數。當建構報告快取數據時，該標籤頁會出現。

- **可快取工作** 顯示哪些編譯器和 build-script 工作復用了快取輸出。搜尋或篩選工作，檢查快取讀/寫延遲，並展開一列以查看其輸出。
- **CAS Outputs** 顯示 artifact 的下載和上傳，包括其大小、持續時間和吞吐量。圖表計算已完成的傳輸；已存在的 artifact 和失敗的嘗試仍保留在表格中。

**命中** 表示復用了快取輸出。**未命中** 表示工作改為進行編譯。命中不會分為本機和遠端；CAS Outputs 顯示記錄的 artifact 操作。

如果詳細記錄缺失或不完整，頁面會顯示通知。摘要仍涵蓋整個建構。估計避免的編譯器工作**並非節省的实际建構時間**。

<!-- @snippet: ../cache/_rust-experimental -->

增量編譯正常進行。

### 執行測試的建構 {#builds-that-run-tests}

`tuist cargo test` 報告整個指令的持續時間，包括其測試。它也透過<.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>報告個別測試結果，包括 doctests。個別測試結果顯示在**Tests**下；指令持續時間顯示在建構洞察中。

## 其他編譯器工具 {#other-compiler-tools}

Tuist 保留透過 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 設定配置的現有編譯器 wrapper，並保持 `RUSTC_WORKSPACE_WRAPPER` 不變。預先存在的全域 wrapper 會停用 Tuist 的快取和編譯器觀察器：Tuist 無法確定該 wrapper 是否實際執行了 rustc。自訂工作區 wrapper 同樣可能導致報告中的編譯器工作較少。

Tuist 透過 rustup 找到 Cargo。如果你使用自訂安裝，請將 `TUIST_CARGO_EXECUTABLE` 設定為其可執行路徑。透過直接工具鏈路徑呼叫 Cargo 會繞過 mise 的 wrapper。Cargo alias 無法取代如 `build` 這樣的內建指令。

如果你使用 Cargo 的 nightly `-C` 選項，請先切換到工作區：Tuist 會轉發 `-C` 指令，但不會收集其建構時間。

## 疑難排解 {#troubleshooting}

如果建構未出現在儀表板中，請啟用 debug 輸出以查看為何其報告未發送：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

報告不會改變你的建構結果。
