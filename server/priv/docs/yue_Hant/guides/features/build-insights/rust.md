---
{
  "title": "Rust 構建洞察",
  "titleTemplate": ":title · 構建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 中找出緩慢的 crate、比較構建效能，並檢查 Rust 編譯器的警告同錯誤。"
}
---
# Rust 編譯洞察 {#rust-build-insights}

Build Insights 幫你找出拖慢 Cargo 編譯的原因，並在影響整個團隊之前捕捉倒退。你可以比較本機編譯與 CI，查看編譯時間變化，並檢查每次編譯中編譯的 crate。

> [!IMPORTANT] Requirements
> - 按照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你的專案並進行身份驗證。

## 報告你的編譯 {#report-your-builds}

透過 Tuist 執行你慣用的 Cargo 指令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link> 以繼續使用普通的 `cargo` 指令。你的參數、工具鏈選擇、輸出和退出碼保持不變。

## 找出拖慢編譯的原因 {#explore-your-builds}

在儀表板的 **Builds → Build Runs** 中開啟一次編譯。使用日期、環境和 Rust 版本篩選器來比較相似的編譯。你也可以透過 `tuist build cargo list` 和 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`，以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 取得編譯及其快取計數。

在 **概覽** 中，使用 **編譯器工作** 找出緩慢的 crate。依 **持續時間** 或 **開始於之後**（自 Cargo 指令開始後的時間）排序，或依 crate 名稱或根原始檔搜尋。

每一列代表對一個 crate 的一次 `rustc` 呼叫，該 crate 可能包含多個原始檔。**Crate 根目錄** 標識其根原始檔；持續時間是針對整個編譯器工作，而非僅該檔案。一個 crate 可能因不同的目標或配置而出現多次。編譯器訊息歸類於 **警告** 和 **錯誤**。

## 解讀時間數據 {#timing-boundaries}

編譯持續時間是指整個 Cargo 指令耗費的時間。編譯器工作可以平行執行，因此它們的持續時間總和不等於編譯持續時間。

Cargo 只會編譯需要重新編譯的 crate。已經最新的 crate 不會出現在編譯器列表中。使用 Tuist 的編譯快取時，還原的工作會出現在快取測量中，而非作為編譯器執行。

Tuist 不會單獨測量建置腳本或顯示編譯時間軸。大型編譯會顯示前 500 個編譯器工作，如果記錄了更多工作則會顯示通知。

## 解讀快取測量 {#cache-measurements}

`tuist cargo` 包含在 Tuist CLI 中實作的實驗性編譯快取。請參閱 <.localized_link href="/guides/features/cache/rust">Rust 快取指南</.localized_link> 以了解設定、透過 Kura 進行遠端讀寫、支援的編譯類型以及疑難排解。

在專案側邊欄中開啟 **Cargo Cache** 以追蹤跨編譯的快取命中率及記錄的傳輸、延遲和吞吐量測量。依日期或環境篩選，切換每日趨勢與單次編譯命中率，或開啟最近的編譯以檢查其快取活動。沒有快取測量的編譯會顯示為不可用，而非計為零。

開啟編譯的 **快取** 分頁以查看工作命中、工作未命中、命中率，以及下載和上傳的位元組數。當編譯報告快取數據時，此分頁才會出現。

- **可快取工作** 顯示哪些編譯器和建置腳本工作復用了快取輸出。搜尋或篩選工作，檢查快取讀/寫延遲，並展開列以查看其輸出。
- **CAS 輸出** 顯示工件的下載和上傳，包括其大小、持續時間和吞吐量。圖表統計已完成的傳輸；已存在的工件和失敗的嘗試仍保留在表格中。

**命中** 表示復用了快取輸出。**未命中** 表示工作改為進行編譯。命中不分本地和遠端；CAS 輸出顯示記錄的工件操作。

如果詳細記錄缺失或不完整，頁面會顯示通知。摘要仍然涵蓋整個編譯。估計避免的編譯器工作 **並非節省的实际編譯時間**。

> [!WARNING] Experimental compilation cache
> 第一個版本僅快取具有已驗證輸入和輸出的註冊表葉節點庫。工作區 crate、建置腳本、過程宏、對其他 crate 的依賴、增量編譯、原生連結和可執行文件正常編譯。快取鍵保留絕對路徑，因此尚不支援在不同檢出路徑間復用。

### 執行測試的編譯 {#builds-that-run-tests}

`tuist cargo test` 報告整個指令的持續時間，包括其測試。它還透過 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link> 報告個別測試結果，包括 doctests。個別測試結果顯示在 **測試** 下；指令持續時間顯示在編譯洞察中。

## 其他編譯器工具 {#other-compiler-tools}

Tuist 保留透過 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 配置設定的現有編譯器包裝器，並保持 `RUSTC_WORKSPACE_WRAPPER` 不變。預先存在的全域包裝器會停用 Tuist 的快取和編譯器觀察器：Tuist 無法確定該包裝器是否實際執行了 rustc。自訂工作區包裝器同樣可能導致報告中的編譯器工作較少。

Tuist 透過 rustup 尋找 Cargo。如果你使用自訂安裝，將 `TUIST_CARGO_EXECUTABLE` 設定為其可執行檔路徑。透過直接工具鏈路徑呼叫 Cargo 會繞過 mise 的包裝器。Cargo 別名無法取代如 `build` 等內建指令。

如果你使用 Cargo 的 nightly `-C` 選項，請先切換到工作區目錄：Tuist 會轉發 `-C` 指令，但不會收集其編譯時間數據。

## 疑難排解 {#troubleshooting}

如果編譯未出現在儀表板中，啟用除錯輸出以查看為何未發送其報告：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

報告不會改變你的編譯結果。
