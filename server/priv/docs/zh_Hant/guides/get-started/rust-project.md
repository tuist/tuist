---
{
  "title": "Rust 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將你的 Rust 專案與 Tuist 連接，以追蹤建置與測試（包含文件測試），並找出不穩定測試。"
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

Tuist 可與你現有的 Cargo 專案搭配運作。你不需要新增 Rust 相依性，也不需要變更專案的建置方式。

## 連接專案

安裝 <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> 與 Rust。在儀表板中建立專案，並將建置系統設為 **Cargo (Rust)**。接著將專案加入工作區根目錄的 `Cargo.toml`：

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo 會忽略 `metadata` 表格，因此這不會改變專案的建置方式。若為單一 crate 且沒有 `[workspace]` 表格，請改用 `[package.metadata.tuist]`。該表格接受的設定與 `tuist.toml` 檔案相同，你也可以改用該檔案，例如當儲存庫中也包含其他建置系統的專案時。若兩者同時存在，`tuist.toml` 優先。

使用 `tuist auth login` 登入，然後透過 Tuist 執行你慣用的 Cargo 指令。在 CI 中，使用 CI 提供者的 OIDC 身分進行驗證，或將 `TUIST_TOKEN` 設為 <.localized_link href="/guides/server/authentication#account-tokens">帳號權杖</.localized_link>。你也可以設定 `TUIST_PROJECT` 而非新增設定檔；若使用自行託管的伺服器，則設定 `TUIST_URL`。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

使用你通常傳遞給 Cargo 的相同引數，包括功能、工具鏈與測試篩選器。即使 Tuist 無法上傳報告，Cargo 仍會保留其慣用的輸出與結束碼。

## 繼續輸入 Cargo

啟用 [mise 的命令包裝器](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) 後，將以下內容加入 `mise.toml`：

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

新增包裝器後執行 `mise reshim`。接著你就可以照常使用 `cargo build`、`cargo check` 與 `cargo test`。Mise 會透過 Tuist 為你執行這些指令。

> [!TIP] Coding agents
> 這在使用編碼代理程式時很有用：它們可以持續執行 `cargo build` 與 `cargo test`，而不需要被提醒加上 `tuist` 前綴。

## 編譯快取

`tuist cargo build` 會自動快取符合資格的編譯、相依性與建置腳本執行，包括本機與透過 Kura 的遠端快取。不需要額外的工具或快取設定。此快取為實驗性功能，已在 Apple silicon Mac 上通過驗證，但尚未涵蓋所有編譯。請參閱 <.localized_link href="/guides/features/cache/rust">Rust 快取</.localized_link> 以了解支援的編譯、驗證方式，以及如何確認重用。

## 建置洞察

在儀表板中開啟 **Builds**，查看建置耗時並比較本機建置與 CI。選擇一個建置，找出編譯時間最長的 crate，並檢查其警告與錯誤。

編譯器計時是以 crate 為單位，而非個別原始檔。請參閱 <.localized_link href="/guides/features/build-insights/rust">Rust 建置洞察</.localized_link> 以了解更多關於解讀建置報告的資訊。

## 測試洞察

照常執行你的測試：

```sh
tuist cargo test --workspace
```

在儀表板中開啟 **Tests**，查看通過、失敗與忽略的測試，包含文件測試。Cargo 會回報測試套件的持續時間，但穩定的 libtest 並未揭露每個測試的計時。

若僅要執行文件測試：

```sh
tuist cargo test --doc
```

請參閱 <.localized_link href="/guides/features/test-insights/rust">Rust 測試洞察</.localized_link> 與 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust 不穩定測試</.localized_link> 以了解更多。

## 商標 {#trademarks}

Rust 與 Cargo 是 Rust Foundation 的商標。Tuist 與 Rust Project 或 Rust Foundation 並無隸屬或背書關係。本指南中的 Rust 標誌 © Rust Foundation，依據 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 授權使用，並以符合頁面主題的單色呈現。
