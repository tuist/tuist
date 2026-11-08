---
{
  "title": "Rust 專案",
  "titleTemplate": ":title · 入門指南 · 教學 · Tuist",
  "description": "將你的 Rust 專案連接至 Tuist，以追蹤建構與測試（包括文件測試），並找出不穩定測試。"
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

- 使用 Cargo 建置的 Rust 專案。
- Tuist CLI 同 Tuist 帳戶。

Tuist 可以同你現有嘅 Cargo 專案配合使用。你唔需要新增 Rust 依賴項，亦都唔需要改變專案嘅建置方式。

## 連接專案

安裝 <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> 同 Rust。喺儀表板建立一個專案，並選擇 **Cargo (Rust)** 作為其建置系統。喺你嘅儲存庫根目錄新增 `tuist.toml`：

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

使用 `tuist auth login` 登入，然後透過 Tuist 執行你平常用嘅 Cargo 指令。喺 CI 中，使用你嘅 CI 供應商嘅 OIDC 身份進行驗證，或者將 `TUIST_TOKEN` 設定為 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。你亦都可以設定 `TUIST_PROJECT` 而唔需要新增設定檔案，如果你使用自託管伺服器，則設定 `TUIST_URL`。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

使用你平時傳畀 Cargo 嘅相同參數，包括功能、工具鏈同測試篩選器。即使 Tuist 無法上載報告，Cargo 仍然會保持其通常嘅輸出同退出代碼。

## 繼續輸入 Cargo

啟用 [mise 嘅命令包裝器](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) 後，將以下內容新增到 `mise.toml`：

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

新增包裝器後執行 `mise reshim`。之後你可以照常使用 `cargo build`、`cargo check` 同 `cargo test`。Mise 會幫你透過 Tuist 執行呢啲指令。

> [!TIP] Coding agents
> 呢個功能喺同編碼代理協作時好有用：佢哋可以繼續執行 `cargo build` 同 `cargo test`，而唔需要提醒佢哋新增 `tuist` 前綴。

## 編譯快取

`tuist cargo build` 會自動快取符合條件嘅編譯、依賴項同建置腳本執行，包括本地同透過 Kura 嘅遠端快取。唔需要額外嘅工具或快取設定。呢個快取功能處於實驗階段，已喺 Apple silicon Mac 上通過驗證，但尚未涵蓋所有編譯。請參閱 <.localized_link href="/guides/features/cache/rust">Rust 快取</.localized_link> 以了解支援嘅編譯、驗證方法同如何驗證重用。

## 建置洞察

喺儀表板開啟 **Builds**，查看你嘅建置耗時，並比較本地建置同 CI 建置。選擇一個建置以找出編譯時間最長嘅 crate，並檢查其警告同錯誤。

編譯器計時係針對 crate，而唔係個別原始碼檔案。請參閱 <.localized_link href="/guides/features/build-insights/rust">Rust 建置洞察</.localized_link> 以了解更多關於閱讀建置報告嘅資訊。

## 測試洞察

照常執行你嘅測試：

```sh
tuist cargo test --workspace
```

喺儀表板開啟 **Tests**，查看通過、失敗同忽略嘅測試，包括 doctests。Cargo 會報告套件持續時間，但穩定版 libtest 並未公開每個測試嘅計時。

要只執行 doctests：

```sh
tuist cargo test --doc
```

請參閱 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link> 同 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust 不穩定測試</.localized_link> 以了解更多。
