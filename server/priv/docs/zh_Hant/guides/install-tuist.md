---
{
  "title": "安裝 Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "使用 mise 或 Homebrew 在 macOS 或 Linux 上安裝 Tuist 命令列介面，並為團隊與持續整合固定版本。"
}
---
# 安裝 Tuist {#install-tuist}

Tuist 命令列介面可在 **macOS** 與 **Linux** 上執行，並將你的 Xcode、已產生的專案、Gradle、Bazel 與 Rust 專案連接至 Tuist 的快取、洞察與執行器基礎設施。雖然你可以從[原始碼](https://github.com/tuist/tuist)建置 Tuist，我們仍建議使用下方的其中一種安裝方式，以確保安裝有效且可驗證。Elixir 專案會改用 `tuist_ex` Hex 套件，不需要安裝 CLI。

## Mise {#recommended-mise}

> [!NOTE]
> 若你尚未安裝 Mise，請先參閱[入門指南](https://mise.jdx.dev/getting-started.html)。如果你所屬的團隊或組織需要確保不同環境中的工具版本具決定性，Mise 是[Homebrew](https://brew.sh)的推薦替代方案。


與 Homebrew 等會在全域安裝並啟用單一版本的工具不同，**Mise 會固定版本**，可設為全域或以專案為範圍。執行 `mise use` 以安裝並啟用 Tuist：

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

若你複製的專案已在 `mise.toml` 中固定了 Tuist 版本，請執行 `mise install` 進行安裝。

> [!TIP]
> `tuist@latest` 會解析為最新的**穩定**版本。Tuist 也會發布預釋版的 canary 與候選版本；這些版本需手動選擇，絕不會由 `latest` 解析。請參閱<.localized_link href="/cli/release/channels">發布頻道</.localized_link>，了解如何固定你可信賴的穩定版本線，以及如何選擇加入預釋版。

<details>
<summary>Linux 支援</summary>

在 Linux 上，Tuist 僅能透過 Mise 取得。依賴 Xcode 的命令（例如 `tuist generate`）在 Linux 上無法使用，但平台無關的命令（例如 `tuist inspect bundle`）則可正常運作。

</details>


## Homebrew（僅限 macOS）{#recommended-homebrew}

你可以使用[Homebrew](https://brew.sh)與[我們的 formula](https://github.com/tuist/homebrew-tuist)來安裝 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **驗證二進位檔的真实性**
>
> 你可以執行以下指令來驗證安裝的二進位檔是否由我們建置，該指令會檢查憑證的團隊識別碼是否為 `U6LC622NKF`：
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 代理 {#http-proxy}

若你的網路將出站流量透過 HTTP 代理轉送，請參閱<.localized_link href="/guides/integrations/http-proxy">HTTP 代理指南</.localized_link>。
