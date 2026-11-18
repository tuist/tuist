---
{
  "title": "Rust 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將你的 Rust 專案連接到 Tuist，以追蹤構建和測試（包括文件測試），並找出不穩定測試。"
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
- Tuist CLI 和 Tuist 帳戶。

Tuist 可與你現有的 Cargo 專案配合使用。你無須新增 Rust 相依項目，亦無須更改專案的建置方式。

## 連接專案

安裝 <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> 和 Rust。在儀表板中建立專案，並將建置系統設為 **Cargo (Rust)**。然後將專案加入工作區根目錄的 `Cargo.toml`：

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo 會忽略 `metadata` 表格，因此這不會改變你的專案建置方式。對於沒有 `[workspace]` 表格的單一 crate，請改用 `[package.metadata.tuist]`。該表格接受與 `tuist.toml` 檔案相同的設定，你可以改用該檔案，例如當儲存庫中包含其他建置系統的專案時。若兩者同時存在，`tuist.toml` 具有優先權。

使用 `tuist auth login` 登入，然後透過 Tuist 執行你慣用的 Cargo 指令。在 CI 中，使用你的 CI 供應商的 OIDC 身分進行驗證，或將 `TUIST_TOKEN` 設為 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link>。你也可以設定 `TUIST_PROJECT` 而無需新增設定檔，若你使用自託管伺服器，則可設定 `TUIST_URL`。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

使用你通常傳遞給 Cargo 的相同引數，包括功能、工具鏈和測試篩選器。即使 Tuist 無法上傳報告，Cargo 仍會保留其慣用的輸出和退出碼。

## 繼續輸入 Cargo

啟用 [mise 的指令包裝器](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) 後，將以下內容加入 `mise.toml`：

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

新增包裝器後執行 `mise reshim`。之後你可以照常使用 `cargo build`、`cargo check` 和 `cargo test`。Mise 會為你透過 Tuist 執行這些指令。

> [!TIP] Coding agents
> 這在使用編碼代理程式時很有用：它們可以持續執行 `cargo build` 和 `cargo test`，而無須被提醒加上 `tuist` 前綴。

## 編譯快取

`tuist cargo build` 會自動快取符合條件的編譯、相依項目和建置腳本執行，包括本機和透過 Kura 的遠端快取。無須額外工具或快取設定。此快取處於實驗階段，已在 Apple silicon Mac 上通過驗證，但尚未涵蓋所有編譯。請參閱 <.localized_link href="/guides/features/cache/rust">Rust 快取</.localized_link> 以了解支援的編譯、驗證方式以及如何驗證重用。

## 建置洞察

在儀表板中開啟 **Builds**，查看建置耗時並比較本機建置與 CI 建置。選擇一個建置以找出編譯時間最長的 crates，並檢查其警告和錯誤。

編譯器計時是針對 crates，而非個別原始檔。請參閱 <.localized_link href="/guides/features/build-insights/rust">Rust 建置洞察</.localized_link> 以了解更多關於讀取建置報告的資訊。

## 測試洞察

照常執行你的測試：

```sh
tuist cargo test --workspace
```

在儀表板中開啟 **Tests**，查看通過、失敗和忽略的測試，包括 doctests。Cargo 會報告套件持续时间，但穩定的 libtest 並未提供每個測試的計時。

僅執行 doctests：

```sh
tuist cargo test --doc
```

在 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link> 和 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust 不穩定測試</.localized_link> 中閱讀更多資訊。

## 商標 {#trademarks}

Rust 和 Cargo 是 Rust Foundation 的商標。Tuist 與 Rust Project 或 Rust Foundation 並無附屬關係，亦未獲得其認可。這些指南中的 Rust 標誌 © Rust Foundation，依據 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 授權使用，並以符合頁面主題的單色顯示。
