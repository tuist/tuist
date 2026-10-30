---
{
  "title": "Rust 建置洞察",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 中找出耗時的 crate、比較建置效能，並檢視 Rust 編譯器的警告與錯誤。"
}
---
# Rust 建置洞察 {#rust-build-insights}

Build Insights 協助你找出拖慢 Cargo 建置的因素，並在影響整個團隊之前捕捉回歸問題。你可以將本機建置與 CI 進行比較，觀察建置時間的變化，並檢查每次建置中編譯的 crate。

> [!IMPORTANT] Requirements
> - 請依照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你的專案並完成驗證。

## 回報你的建置 {#report-your-builds}

透過 Tuist 執行你慣用的 Cargo 指令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link> 以繼續使用一般的 `cargo` 指令。你的參數、工具鏈選擇、輸出與結束碼都保持不變。

## 找出拖慢建置的因素 {#explore-your-builds}

在儀表板的 **Builds → Build Runs** 中開啟一個建置。使用日期、環境與 Rust 版本篩選器來比較相似的建置。你也可以透過 `tuist build cargo list` 與 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`，以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 取得建置與其快取計數。

在 **Overview** 中，使用 **Compiler jobs** 找出耗時的 crate。依 **Duration** 或 **Started after**（自 Cargo 指令啟動後的時間）排序，或依 crate 名稱或根原始檔搜尋。

每一列代表對某個 crate 的一次 `rustc` 呼叫，該 crate 可能包含多個原始檔。**Crate root** 標示其根原始檔；持續時間是整個編譯器工作的時間，而非僅該檔案。同一個 crate 可能因不同目標或設定而出現多次。編譯器訊息會歸類於 **Warnings** 與 **Errors**。

## 解讀時間數據 {#timing-boundaries}

建置持續時間是指整個 Cargo 指令所花費的時間。編譯器工作可以平行執行，因此它們的持續時間總和不會等於建置持續時間。

Cargo 只會編譯需要重新建置的 crate。已為最新的 crate 不會出現在編譯器清單中。使用 Tuist 的編譯快取時，還原的工作會顯示在快取測量中，而非作為編譯器執行。

Tuist 不會單獨測量建置腳本，也不會顯示建置時間軸。大型建置會顯示前 500 個編譯器工作，若記錄了更多工作則會顯示提示。

## 解讀快取測量 {#cache-measurements}

`tuist cargo` 包含由 Tuist CLI 實作的實驗性編譯快取。請參閱 <.localized_link href="/guides/features/cache/rust">Rust 快取指南</.localized_link> 以了解設定、透過 Kura 進行的遠端讀寫、支援的編譯，以及疑難排解。

在專案側邊欄中開啟 **Cargo Cache**，以追蹤跨建置的快取命中率，以及記錄的傳輸、延遲與吞吐量測量。依日期或環境篩選，切換每日趨勢與個別建置的命中率，或開啟近期的建置以檢查其快取活動。沒有快取測量的建置之資料仍顯示為不可用，而非計為零。

開啟建置的 **Cache** 分頁，查看工作命中、工作未命中、命中率，以及下載與上傳的位元組數。當建置回報快取資料時，此分頁才會出現。

- **Cacheable Tasks** 顯示哪些編譯器與建置腳本工作重複使用了快取輸出。你可以搜尋或篩選這些工作、檢查快取讀寫延遲，並展開列以查看其輸出。
- **CAS Outputs** 顯示構件的下載與上傳，包含其大小、持續時間與吞吐量。圖表統計已完成的傳輸；已存在的構件與失敗嘗試仍會保留在表格中。

**Hit** 表示重複使用了快取輸出。**Missed** 表示該工作改為執行編譯。命中不會區分為本機與遠端；CAS Outputs 會顯示記錄的構件操作。

如果詳細記錄遺失或不完整，頁面會顯示提示。摘要仍涵蓋整個建置。估計避免的編譯器工作 **不等於節省的实际建置時間**。

> [!WARNING] Experimental compilation cache
> 第一個版本僅快取具有已驗證輸入與輸出的註冊表葉節點函式庫。工作區 crate、建置腳本、程序巨集、對其他 crate 的相依性、增量編譯、原生連結，以及可執行檔皆正常建置。快取金鑰保留絕對路徑，因此尚不支援在不同檢出路徑之間重複使用。

### 執行測試的建置 {#builds-that-run-tests}

`tuist cargo test` 會回報整個指令的持續時間，包含其測試。它也透過 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> 回報個別測試結果，包含文件測試。個別測試結果顯示在 **Tests** 下方；指令持續時間則顯示在建置洞察中。

## 其他編譯器工具 {#other-compiler-tools}

Tuist 會保留透過 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 設定設定的現有編譯器包裝器，並保持 `RUSTC_WORKSPACE_WRAPPER` 不變。若存在全域包裝器，會停用 Tuist 的快取與編譯器觀察器：Tuist 無法確認該包裝器是否確實執行了 rustc。自訂工作區包裝器也可能導致報告中的編譯器工作較少。

Tuist 透過 rustup 尋找 Cargo。如果你使用自訂安裝，請將 `TUIST_CARGO_EXECUTABLE` 設為其可執行檔路徑。直接以工具鏈路徑呼叫 Cargo 會繞過 mise 的包裝器。Cargo 別名無法取代內建指令，例如 `build`。

如果你使用 Cargo 的 nightly `-C` 選項，請先切換至工作區目錄：Tuist 會轉發 `-C` 指令，但不會收集其建置時間。

## 疑難排解 {#troubleshooting}

如果建置未出現在儀表板中，請啟用除錯輸出以查看為何未送出報告：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

回報不會改變你的建置結果。
