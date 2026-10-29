---
{
  "title": "Rust Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Find slow crates, compare build performance, and inspect Rust compiler warnings and errors in Tuist."
}
---
# Rust 建置洞察 {#rust-build-insights}

Build Insights 協助您找出拖慢 Cargo 建置速度的原因，並在影響整個團隊之前捕捉回歸問題。您可以將本機建置與 CI 進行比較，查看建置時間的變化，並檢查每次建置中編譯的 crate。

> [!IMPORTANT] Requirements
> - 請依照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 來連接您的專案並進行驗證。

## 回報您的建置 {#report-your-builds}

透過 Tuist 執行您慣用的 Cargo 指令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果您使用 mise，請 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link> 以繼續使用一般的 `cargo` 指令。您的參數、工具鏈選擇、輸出和結束代碼保持不變。

## 找出拖慢建置速度的原因 {#explore-your-builds}

在儀表板上從 **Builds → Build Runs** 開啟一個建置。使用日期、環境和 Rust 版本篩選器來比較相似的建置。您也可以透過 `tuist build cargo list` 和 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`，以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 取得建置及其快取計數器。

在 **Overview** 中，使用 **Compiler jobs** 來找出緩慢的 crate。依 **Duration** 或 **Started after**（自 Cargo 指令開始後經過的時間）排序，或依 crate 名稱或根原始檔搜尋。

每一列代表對一個 crate 的一次 `rustc` 叫用，該 crate 可能包含多個原始檔。**Crate root** 標示其根原始檔；持續時間是針對整個編譯器工作，而非僅該檔案。一個 crate 可能因不同的目標或設定而出現多次。編譯器訊息會歸類在 **Warnings** 和 **Errors** 中。

## 解讀時間數據 {#timing-boundaries}

建置持續時間是指整個 Cargo 指令所花費的時間。編譯器工作可以平行執行，因此它們的持續時間總和不會等於建置持續時間。

Cargo 只會編譯需要重新建置的 crate。已經是最新狀態的 crate 不會出現在編譯器清單中。使用 Tuist 的編譯快取時，還原的工作會顯示在快取測量中，而不是作為編譯器執行。

Tuist 不會單獨測量建置腳本，也不會顯示建置時間軸。大型建置會顯示前 500 個編譯器工作，如果記錄了更多工作則會顯示通知。

## 解讀快取測量數據 {#cache-measurements}

`tuist cargo` 包含一個在 Tuist CLI 中實作的實驗性編譯快取。請依照 <.localized_link href="/guides/features/cache/rust">Rust 快取指南</.localized_link> 進行設定、透過 Kura 進行遠端讀寫、了解支援的編譯類型，以及進行疑難排解。

在專案側邊欄中開啟 **Cargo Cache**，以追蹤跨建置的快取命中率，以及記錄的傳輸、延遲和吞吐量測量數據。依日期或環境篩選，在每日趨勢和單次建置命中率之間切換，或開啟最近的建置以檢查其快取活動。沒有快取測量數據的建置會顯示為不可用，而不是計為零。

開啟建置的 **Cache** 分頁，以查看工作命中、工作未命中、命中率，以及下載和上傳的位元組數。當建置回報快取數據時，此分頁才會出現。

- **Cacheable Tasks** 顯示哪些編譯器和建置腳本工作重複使用了快取的輸出。您可以搜尋或篩選工作、檢查快取讀取/寫入延遲，並展開資料列以查看其輸出。
- **CAS Outputs** 顯示構件的下載和上傳，包括其大小、持續時間和吞吐量。圖表統計已完成的傳輸；已存在的構件和失敗的嘗試仍會保留在表格中。

**Hit** 表示重複使用了快取的輸出。**Missed** 表示工作改為進行編譯。命中不會區分為本機和遠端；CAS Outputs 會顯示記錄的構件操作。

如果詳細記錄遺失或不完整，頁面會顯示通知。摘要仍然涵蓋整個建置。估計避免的編譯器工作量 **並非節省的实际建置時間**。

> [!WARNING] Experimental compilation cache
> 第一個版本僅快取具有已驗證輸入和輸出的登錄檔葉節點函式庫。工作區 crate、建置腳本、過程巨集、對其他 crate 的依賴、增量編譯、原生連結和可執行檔會正常建置。快取金鑰保留絕對路徑，因此尚不支援在不同檢出路徑之間重複使用。

### 執行測試的建置 {#builds-that-run-tests}

`tuist cargo test` 會回報整個指令的持續時間，包括其測試。它也會透過 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> 回報個別測試結果，包括文件測試。個別測試結果會顯示在 **Tests** 下方；指令持續時間則顯示在建置洞察中。

## 其他編譯器工具 {#other-compiler-tools}

Tuist 會保留透過 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 設定設定的現有編譯器包裝器，並保持 `RUSTC_WORKSPACE_WRAPPER` 不變。預先存在的全域包裝器會停用 Tuist 的快取和編譯器觀察器：Tuist 無法確定該包裝器是否實際執行了 rustc。自訂工作區包裝器同樣可能導致報告中的編譯器工作較少。

Tuist 透過 rustup 尋找 Cargo。如果您使用自訂安裝，請將 `TUIST_CARGO_EXECUTABLE` 設定為其可執行檔路徑。透過直接工具鏈路徑呼叫 Cargo 會繞過 mise 的包裝器。Cargo 別名無法取代內建指令，例如 `build`。

如果您使用 Cargo 的 nightly `-C` 選項，請先切換到工作區目錄：Tuist 會轉發 `-C` 指令，但不會收集它們的建置時間數據。

## 疑難排解 {#troubleshooting}

如果建置未出現在儀表板上，請啟用偵錯輸出以查看為何未傳送其報告：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

回報不會改變您建置的結果。
