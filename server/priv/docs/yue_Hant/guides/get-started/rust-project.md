---
{
  "title": "Rust project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect your Rust project to Tuist to track builds and tests, including doctests, and find flaky tests."
}
---
# Rust 專案 {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## 先決條件

- 使用 Cargo 建構的 Rust 專案。
- Tuist CLI 和 Tuist 帳戶。

Tuist 可與你現有的 Cargo 專案配合使用。你無需新增 Rust 相依性或變更專案的建構方式。

## 連接專案

安裝 <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> 和 Rust。在儀表板中建立專案，並選擇 **Cargo (Rust)** 作為其建構系統。在你的儲存庫根目錄新增 `tuist.toml`：

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

使用 `tuist auth login` 登入，然後透過 Tuist 執行你慣用的 Cargo 指令。在 CI 中，將 `TUIST_TOKEN` 設定為專案權杖。如果你使用自託管伺服器，也可以設定 `TUIST_PROJECT` 而非新增設定檔，以及設定 `TUIST_URL`。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

使用你通常傳遞給 Cargo 的相同參數，包括功能、工具鏈和測試篩選器。即使 Tuist 無法上傳報告，Cargo 仍會保持其 usual 輸出和結束代碼。

## 繼續輸入 Cargo

啟用 [mise 的指令包裝器](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) 後，將此內容新增至 `mise.toml`：

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

新增包裝器後執行 `mise reshim`。之後你可以照常使用 `cargo build`、`cargo check` 和 `cargo test`。Mise 會為你透過 Tuist 執行這些指令。

> [!TIP] Coding agents
> 這在使用編碼代理程式時很有用：它們可以持續執行 `cargo build` 和 `cargo test`，而無需提醒它們新增 `tuist` 前綴。

## 編譯快取

`tuist cargo build` 會自動快取符合資格的註冊表葉節點函式庫，包括本機和透過 Kura 的遠端快取。無需額外的工具或快取設定。此快取功能處於實驗階段，尚未涵蓋所有編譯或在不同檢出路徑之間的重用。請參閱 <.localized_link href="/guides/features/cache/rust">Rust 快取</.localized_link> 以了解支援的編譯、驗證方式以及如何確認重用。

## 建構洞察

在儀表板中開啟 **Builds**，查看你的建構耗時並比較本機建構與 CI 建構。選擇一個建構以找出編譯時間最長的 crate，並檢查其警告和錯誤。

編譯器計時是針對 crate，而非個別原始碼檔案。請參閱 <.localized_link href="/guides/features/build-insights/rust">Rust 建構洞察</.localized_link> 以了解更多關於讀取建構報告的資訊。

## 測試洞察

照常執行你的測試：

```sh
tuist cargo test --workspace
```

在儀表板中開啟 **Tests**，查看通過、失敗和忽略的測試，包括文件測試。Cargo 會報告套件持續時間，但穩定的 libtest 並未公開每個測試的計時。

僅執行文件測試：

```sh
tuist cargo test --doc
```

請參閱 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link> 和 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust 不穩定測試</.localized_link> 以了解更多。
