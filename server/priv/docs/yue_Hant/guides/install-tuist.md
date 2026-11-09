---
{
  "title": "安裝 Tuist",
  "titleTemplate": ":title · 指南 · Tuist",
  "description": "使用 mise 或 Homebrew 在 macOS 或 Linux 上安裝 Tuist 命令列介面，並為團隊和持續整合鎖定版本。"
}
---
# 安裝 Tuist {#install-tuist}

Tuist 命令列介面可在 **macOS** 和 **Linux** 上執行，並將你的 Xcode、已產生、Gradle、Bazel 及 Rust 專案連接到 Tuist 的快取、洞察與執行器基礎設施。雖然你可以從[原始碼](https://github.com/tuist/tuist)編譯 Tuist，但我們建議使用以下其中一種安裝方法，以確保安裝有效且可驗證。Elixir 專案則改用 `tuist_ex` Hex 套件，不需要 CLI。

## Mise {#recommended-mise}

> [!NOTE]
> 如果你尚未安裝 Mise，請先參閱[入門指南](https://mise.jdx.dev/getting-started.html)。如果你的團隊或組織需要確保在不同環境中使用確定性的工具版本，Mise 是 [Homebrew](https://brew.sh) 的推薦替代方案。


與 Homebrew 等會在全域安裝並啟用單一版本工具不同，**Mise 會鎖定版本**，可設為全域或限定於專案範圍。執行 `mise use` 以安裝並啟用 Tuist：

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

如果你複製的專案已在 `mise.toml` 中鎖定 Tuist 版本，請執行 `mise install` 來安裝。

> [!TIP]
> `tuist@latest` 會解析為最新的 **穩定** 版本。Tuist 也會發布預發布的 canary 和候選版本；這些版本僅限手動選用，絕不會由 `latest` 解析。請參閱 <.localized_link href="/cli/release/channels">發布渠道</.localized_link>，了解如何鎖定你可信賴的穩定版本線，以及如何選用預發布版本。

<details>
<summary>Linux 支援</summary>

在 Linux 上，Tuist 僅可透過 Mise 取得。依賴 Xcode 的命令（例如 `tuist generate`）在 Linux 上不可用，但平台無關的命令如 `tuist inspect bundle` 則可正常運作。

</details>


## Homebrew（僅限 macOS）{#recommended-homebrew}

你可以使用 [Homebrew](https://brew.sh) 和 [我們的 formula](https://github.com/tuist/homebrew-tuist) 來安裝 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **驗證二進位檔的真偽**
>
> 你可以執行以下命令來驗證安裝的二進位檔是否由我們建構，該命令會檢查憑證的團隊 ID 是否為 `U6LC622NKF`：
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 代理 {#http-proxy}

如果你的網路將出站流量透過 HTTP 代理路由，請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理指南</.localized_link>。
