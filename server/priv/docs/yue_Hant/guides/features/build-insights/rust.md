---
{
  "title": "Rust Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Find slow crates, compare build performance, and inspect Rust compiler warnings and errors in Tuist."
}
---
# Rust 構建洞察 {#rust-build-insights}

Build Insights 幫助你找出拖慢 Cargo 構建速度的原因，並在問題影響整個團隊之前捕捉到回歸錯誤。你可以將本地構建與 CI 進行比較，查看構建時間的變化，並檢查每次構建中編譯的 crate。

> [!IMPORTANT] Requirements
> - 請按照 <.localized_link href="/guides/get-started/rust-project">Rust 專案設置</.localized_link> 連接你的專案並進行身份驗證。

## 報告你的構建 {#report-your-builds}

透過 Tuist 執行你常用的 Cargo 命令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">配置 Cargo 包裝器</.localized_link> 以繼續使用普通的 `cargo` 命令。你的參數、工具鏈選擇、輸出和退出碼保持不變。

## 找出拖慢構建速度的原因 {#explore-your-builds}

在儀表板上從 **構建 → 構建運行** 打開一個構建。使用日期、環境和 Rust 版本過濾器來比較相似的構建。構建及其緩存計數器也可通過 `tuist build cargo list` 和 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds` 以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 獲取。

在 **概覽** 中，使用 **編譯器任務** 查找緩慢的 crate。按 **持續時間** 或 **開始於之後**（自 Cargo 命令開始以來的時間）排序，或按 crate 名稱或根源文件搜索。

每一行代表對一個 crate 的一次 `rustc` 調用，該 crate 可能包含多個源文件。**Crate 根目錄** 標識其根源文件；持續時間是針對整個編譯器任務，而不僅是該文件。一個 crate 可能因不同的目標或配置而出現多次。編譯器消息分組在 **警告** 和 **錯誤** 中。

## 閱讀計時數據 {#timing-boundaries}

構建持續時間是指整個 Cargo 命令所花費的時間。編譯器任務可以並行運行，因此它們的持續時間總和不等於構建持續時間。

Cargo 僅編譯需要重新構建的 crate。已經最新的 crate 不會出現在編譯器列表中。使用 Tuist 的編譯緩存時，恢復的任務會顯示在緩存測量中，而不是作為編譯器執行。

Tuist 不會單獨測量構建腳本或顯示構建時間軸。大型構建會顯示前 500 個編譯器任務，如果記錄了更多任務，則會顯示通知。

## 閱讀緩存測量數據 {#cache-measurements}

`tuist cargo` 包含一個在 Tuist CLI 中實現的实验性編譯緩存。請遵循 <.localized_link href="/guides/features/cache/rust">Rust 緩存指南</.localized_link> 進行設置、通過 Kura 進行遠程讀寫、了解支持的編譯以及故障排除。

在專案側邊欄中打開 **Cargo 緩存** 以跟踪跨構建的緩存命中率以及記錄的傳輸、延遲和吞吐量測量數據。按日期或環境過濾，在每日趨勢和單次構建命中率之間切換，或打開最近的構建以檢查其緩存活動。沒有緩存測量數據的構建仍顯示為不可用，而不是計為零。

打開構建的 **緩存** 標籤頁以查看任務命中、任務未命中、命中率以及下載和上傳的字節數。當構建報告緩存數據時，該標籤頁才會出現。

- **可緩存任務** 顯示哪些編譯器和構建腳本任務復用了緩存輸出。搜索或過濾任務，檢查緩存讀/寫延遲，並展開行以查看其輸出。
- **CAS 輸出** 顯示工件的下載和上傳，包括它們的大小、持續時間和吞吐量。圖表統計已完成的傳輸；已存在的工件和失敗的嘗試仍保留在表中。

**命中** 表示復用了緩存輸出。**未命中** 表示任務改為進行編譯。命中不分為本地和遠程；CAS 輸出顯示記錄的工件操作。

如果詳細記錄缺失或不完整，頁面會顯示通知。摘要仍然涵蓋整個構建。估計避免的編譯器工作 **並非節省的实际構建時間**。

> [!WARNING] Experimental compilation cache
> 第一個版本僅緩存具有已驗證輸入和輸出的註冊表葉子庫。工作區 crate、構建腳本、過程宏、對其他 crate 的依賴、增量編譯、本機鏈接和可執行文件正常構建。緩存鍵保留絕對路徑，因此尚不支持在不同檢出路徑之間重用。

### 運行測試的構建 {#builds-that-run-tests}

`tuist cargo test` 報告整個命令的持續時間，包括其測試。它還通過 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link> 報告單個測試結果，包括文檔測試。單個測試結果顯示在 **測試** 下；命令持續時間顯示在構建洞察中。

## 其他編譯器工具 {#other-compiler-tools}

Tuist 保留通過 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 配置配置的現有編譯器包裝器，並保持 `RUSTC_WORKSPACE_WRAPPER` 不變。預先存在的全局包裝器會禁用 Tuist 的緩存和編譯器觀察器：Tuist 無法確定該包裝器是否實際運行了 rustc。自定義工作區包裝器同樣可能導致報告中的編譯器任務減少。

Tuist 通過 rustup 查找 Cargo。如果你使用自定義安裝，請將 `TUIST_CARGO_EXECUTABLE` 設置為其可執行文件路徑。通過直接工具鏈路徑調用 Cargo 會繞過 mise 的包裝器。Cargo 別名不能替換如 `build` 這樣的內置命令。

如果你使用 Cargo 的 nightly `-C` 選項，請先切換到工作區目錄：Tuist 會轉發 `-C` 命令，但不會收集它們的構建計時數據。

## 故障排除 {#troubleshooting}

如果構建未出現在儀表板上，請啟用調試輸出以查看為何未發送其報告：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

報告不會改變你的構建結果。
