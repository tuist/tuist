---
{
  "title": "Rust 構建分析",
  "titleTemplate": ":title · 構建分析 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 中找出緩慢的 crate、比較構建效能，並檢查 Rust 編譯器的警告同錯誤。"
}
---
# Rust 構建洞察 {#rust-build-insights}

Build Insights 幫你找出拖慢 Cargo 構建嘅原因，並喺影響成個團隊之前捕捉倒退。你可以比較本地構建同 CI，查看構建時間點樣變化，並檢查每次構建中編譯嘅 crate。

> [!IMPORTANT] Requirements
> - 跟隨 <.localized_link href="/guides/get-started/rust-project">Rust 專案設定</.localized_link> 連接你嘅專案並進行身份驗證。

## 匯報你嘅構建 {#report-your-builds}

透過 Tuist 執行你常用嘅 Cargo 命令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">設定 Cargo 包裝器</.localized_link> 以繼續使用普通嘅 `cargo` 命令。你嘅參數、工具鏈選擇、輸出同退出碼保持不變。

## 找出拖慢構建嘅原因 {#explore-your-builds}

喺儀表板嘅 **構建 → 構建運行** 中打開一個構建。使用日期、環境同 Rust 版本過濾器來比較相似嘅構建。構建同佢哋嘅快取計數亦可透過 `tuist build cargo list` 同 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`，以及 `list_cargo_builds` 同 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 獲取。

喺 **概覽** 中，使用 **編譯器任務** 搵出緩慢嘅 crate。按 **持續時間** 或 **開始於之後**（自 Cargo 命令開始以來嘅時間）排序，或按 crate 名稱或根原始檔搜尋。

每一行代表對一個 crate 嘅一次 `rustc` 調用，該 crate 可能包含多個原始檔。**Crate 根目錄** 標識其根原始檔；持續時間係針對整個編譯器任務，而非僅該檔案。一個 crate 可能因不同目標或配置而出現多次。編譯器訊息歸類於 **警告** 同 **錯誤**。

### 跨構建追蹤 crate {#crate-history}

對於參與逐步推出 crate 歷史記錄功能嘅專案，**構建 → Crates** 顯示觀察到嘅 crate 及其編譯歷史。打開一個 crate 以比較其喺不同構建中記錄嘅持續時間同結果，然後追蹤該編譯回到其 Cargo 構建。相同嘅清單亦可透過專案 API 中嘅 `/cargo/crates` 同帶有 `kind: cargo_crates` 嘅共享 MCP 構建實體工具獲取。

Crate 按其精確記錄嘅根路徑、名稱同類型分組。更改檢出路徑可能會分割歷史記錄；配置文件、功能同目標三元組不作區分。這係觀察到嘅編譯器任務清單，並非你工作區中嘅每個 crate。已快取或最新嘅 crate 不會產生編譯樣本。

### 歸屬構建報告 {#report-attribution}

經過身份驗證嘅報告會識別個人憑證背後嘅個人。共享憑證無需識別個人。可選地將 `TUIST_ACTOR_ID` 設置為報告機器上嘅穩定不透明標識符；默認為關閉狀態，並顯示為未經驗證嘅聲明，從不用於授權。較舊嘅伺服器可能會忽略該聲明。切勿將秘密放入其中。

## 解讀計時數據 {#timing-boundaries}

構建持續時間係整個 Cargo 命令所需嘅時間。編譯器任務可以並行運行，因此佢哋嘅持續時間相加唔等於構建持續時間。

Cargo 僅編譯需要重新構建嘅 crate。已經最新嘅 crate 不會出現喺編譯器列表中。使用 Tuist 嘅編譯快取時，恢復嘅任務會顯示喺快取測量中，而非作為編譯器執行。

Tuist 不會單獨測量構建腳本或顯示構建時間軸。大型構建會顯示前 500 個編譯器任務，如果記錄咗更多則會發出通知。

## 解讀快取測量數據 {#cache-measurements}

`tuist cargo` 包含一個喺 Tuist CLI 中實現嘅實驗性編譯快取。請遵循 <.localized_link href="/guides/features/cache/rust">Rust 快取指南</.localized_link> 進行設置、透過 Kura 進行遠程讀寫、了解支持嘅編譯以及故障排除。

喺專案側邊欄中打開 **Cargo 快取** 以追蹤跨構建嘅快取命中率同記錄嘅傳輸、延遲同吞吐量測量數據。按日期或環境過濾，切換每日趨勢同單次構建命中率，或打開最近嘅構建以檢查其快取活動。沒有快取測量數據嘅構建會保持不可用狀態，而唔會計為零。

打開構建嘅 **快取** 標籤頁以查看任務命中、任務未命中、命中率，以及下載同上傳嘅字節數。當構建報告快取數據時，該標籤頁會出現。

- **可快取任務** 顯示哪些編譯器同構建腳本任務重用咗快取輸出。搜尋或過濾任務，檢查快取讀/寫延遲，並展開一行以查看其輸出。
- **CAS 輸出** 顯示工件下載同上傳，包括其大小、持續時間同吞吐量。圖表計算已完成嘅傳輸；已存在嘅工件同失敗嘗試仍保留喺表中。

**命中** 表示重用咗快取輸出。**未命中** 表示任務改為進行編譯。命中唔分為本地同遠程；CAS 輸出顯示記錄嘅工件操作。

如果詳細記錄缺失或不完整，頁面會顯示通知。摘要仍然涵蓋整個構建。估計避免嘅編譯器工作 **並非節省嘅構建經過時間**。

> [!WARNING] Experimental compilation cache
> 第一個版本僅快取具有已驗證輸入同輸出嘅註冊表葉庫。工作區 crate、構建腳本、過程宏、對其他 crate 嘅依賴、增量編譯、本機鏈接同可執行文件正常構建。快取鍵保留絕對路徑，因此尚不支持跨不同檢出路徑嘅重用。

### 運行測試嘅構建 {#builds-that-run-tests}

`tuist cargo test` 報告整個命令嘅持續時間，包括其測試。它亦透過 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link> 報告個別測試結果，包括 doctest。個別測試結果顯示喺 **測試** 下；命令持續時間顯示喺構建洞察中。

## 其他編譯器工具 {#other-compiler-tools}

Tuist 保留透過 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 配置設定嘅現有編譯器包裝器，並保持 `RUSTC_WORKSPACE_WRAPPER` 不變。預先存在嘅全局包裝器會禁用 Tuist 嘅快取同編譯器觀察器：Tuist 無法確定該包裝器是否實際運行咗 rustc。自定義工作區包裝器同樣可能導致報告中嘅編譯器任務減少。

Tuist 透過 rustup 尋找 Cargo。如果你使用自定義安裝，請將 `TUIST_CARGO_EXECUTABLE` 設置為其可執行文件路徑。透過直接工具鏈路徑調用 Cargo 會繞過 mise 嘅包裝器。Cargo 別名無法取代如 `build` 等內置命令。

如果你使用 Cargo 嘅 nightly `-C` 選項，請先切換到工作區：Tuist 會轉發 `-C` 命令，但唔會收集其構建時間。

## 疑難排解 {#troubleshooting}

如果構建未顯示喺儀表板中，請啟用除錯輸出以查看為何其報告未被發送：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

報告唔會改變你構建嘅結果。
