---
{
  "title": "Rust 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將你的 Rust 專案連接至 Tuist，以追蹤建置與測試（包含文件測試），並找出不穩定測試。"
}
---
# Rust 專案 {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## 必要條件

- 使用 Cargo 建置的 Rust 專案。
- Tuist CLI 與 Tuist 帳號。

Tuist 可與你現有的 Cargo 專案搭配使用。你不需要新增 Rust 相依性，也不需要變更專案的建置方式。

## 連接專案

安裝 <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> 與 Rust。在儀表板中建立專案，並將建置系統設為 **Cargo (Rust)**。在儲存庫根目錄新增 `tuist.toml`：

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

使用 `tuist auth login` 登入，然後透過 Tuist 執行你慣用的 Cargo 指令。在 CI 中，將 `TUIST_TOKEN` 設為專案權杖。你也可以設定 `TUIST_PROJECT` 來取代新增設定檔，若使用自架伺服器則可設定 `TUIST_URL`。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

使用你通常傳遞給 Cargo 的相同引數，包括功能、工具鏈與測試篩選器。即使 Tuist 無法上傳報告，Cargo 仍會保留其 usual 輸出與結束碼。

## 繼續輸入 Cargo

啟用 [mise 的命令包裝器](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) 後，將以下內容加入 `mise.toml`：

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

新增包裝器後執行 `mise reshim`。接著你可以照常使用 `cargo build`、`cargo check` 與 `cargo test`。Mise 會代你透過 Tuist 執行這些指令。

> [!TIP] Coding agents
> 這在使用編碼代理程式時很有用：它們可以持續執行 `cargo build` 與 `cargo test`，而不需要被提醒加上 `tuist` 前綴。

## 編譯快取

`tuist cargo build` 會自動快取符合条件的註冊表葉節點函式庫，包含本機與透過 Kura 的遠端快取。不需要額外的工具或快取設定。此快取為實驗性功能，尚未涵蓋所有編譯或在不同檢出路徑間的复用。請參閱 <.localized_link href="/guides/features/cache/rust">Rust cache</.localized_link> 以了解支援的編譯、認證方式，以及如何驗證复用。

## 建置洞察

在儀表板中開啟 **Builds**，查看建置耗時並比較本機建置與 CI 建置。選擇一個建置，找出編譯時間最長的 crate，並檢查其警告與錯誤。

編譯器計時是以 crate 為單位，而非個別原始碼檔案。請參閱 <.localized_link href="/guides/features/build-insights/rust">Rust Build Insights</.localized_link> 以了解更多關於解讀建置報告的資訊。

## 測試洞察

照常執行你的測試：

```sh
tuist cargo test --workspace
```

在儀表板中開啟 **Tests**，查看通過、失敗與忽略的測試，包含文件測試。Cargo 會回報套件總耗時，但穩定的 libtest 並未揭露單一測試的耗時。

僅執行文件測試：

```sh
tuist cargo test --doc
```

請參閱 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> 與 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Flaky Tests</.localized_link> 以了解更多。
