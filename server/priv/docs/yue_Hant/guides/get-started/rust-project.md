---
{
  "title": "Rust 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將你的 Rust 專案連接到 Tuist，以追蹤建構和測試（包括文件測試），並找出問題不穩定測試。"
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

- 一個用 Cargo 建置的 Rust 專案。
- Tuist CLI 同 Tuist 帳戶。

Tuist 可以配合你現有嘅 Cargo 專案運作。你唔需要加入 Rust 依賴項，亦都唔需要更改專案嘅建置方式。

## 連接專案

安裝 <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> 同 Rust。喺儀表板建立一個專案，並選擇 **Cargo (Rust)** 作為其建置系統。然後將專案加入工作區根目錄嘅 `Cargo.toml`：

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo 會忽略 `metadata` 表格，所以呢個設定唔會改變你專案嘅建置方式。如果係單一 crate 而冇 `[workspace]` 表格，就改用 `[package.metadata.tuist]`。該表格接受同 `tuist.toml` 檔案一樣嘅設定，你可以改用佢，例如當儲存庫同時包含其他建置系統嘅專案時。如果兩者都存在，`tuist.toml` 會優先採用。

使用 `tuist auth login` 登入，然後透過 Tuist 執行你平時用嘅 Cargo 指令。喺 CI 環境中，可以使用 CI 供應商嘅 OIDC 身份進行驗證，或者將 `TUIST_TOKEN` 設定為 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。你亦都可以設定 `TUIST_PROJECT` 而唔需要加入設定檔案，如果你使用自託管伺服器，亦可以設定 `TUIST_URL`。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

使用你平時傳畀 Cargo 嘅相同參數，包括功能、工具鏈同測試篩選器。即使 Tuist 無法上載報告，Cargo 仍然會保持其慣常嘅輸出同退出代碼。

## 繼續輸入 Cargo

啟用 [mise 嘅指令包裝器](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) 後，將以下內容加入 `mise.toml`：

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

加入包裝器後執行 `mise reshim`。之後你就可以照常使用 `cargo build`、`cargo check` 同 `cargo test`。Mise 會幫你透過 Tuist 執行呢啲指令。

> [!TIP] Coding agents
> 呢個做法喺同編碼代理程式協作時好有用：佢哋可以繼續執行 `cargo build` 同 `cargo test`，而唔需要提醒佢哋加入 `tuist` 前綴。

## 編譯快取

`tuist cargo build` 會自動快取符合資格嘅編譯、依賴項同建置腳本執行，包括本地同透過 Kura 嘅遠端快取。唔需要額外嘅工具或快取設定。呢個快取功能處於實驗階段，已喺 Apple silicon Mac 上通過驗證，但尚未涵蓋所有編譯。請參閱 <.localized_link href="/guides/features/cache/rust">Rust 快取</.localized_link> 以了解支援嘅編譯、驗證方法以及如何確認重用情況。

## 建置洞察

喺儀表板開啟 **Builds**，查看你嘅建置耗時，並比較本地建置同 CI 建置。選擇一個建置以找出編譯時間最長嘅 crates，並檢查其警告同錯誤。

編譯器計時係針對 crates，而唔係個別原始碼檔案。請參閱 <.localized_link href="/guides/features/build-insights/rust">Rust Build Insights</.localized_link> 以了解更多關於閱讀建置報告嘅資訊。

## 測試洞察

照常執行你嘅測試：

```sh
tuist cargo test --workspace
```

喺儀表板開啟 **Tests**，查看通過、失敗同忽略嘅測試，包括 doctests。Cargo 會報告套件持續時間，但穩定版 libtest 並唔會公開每個測試嘅計時。

如果只想執行 doctests：

```sh
tuist cargo test --doc
```

請參閱 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> 同 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Flaky Tests</.localized_link> 以了解更多。

## 商標 {#trademarks}

Rust 同 Cargo 係 Rust Foundation 嘅商標。Tuist 與 Rust Project 或 Rust Foundation 並無附屬關係，亦未獲得其認可。呢啲指南中嘅 Rust 標誌版權屬於 Rust Foundation，根據 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 授權使用，並以符合頁面主題嘅單色顯示。
