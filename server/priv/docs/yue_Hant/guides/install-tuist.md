---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# 安裝 Tuist {#install-tuist}

Tuist 命令列介面可在 **macOS** 和 **Linux** 上運行，並將你的 Xcode、生成項目、Gradle 和 Bazel 項目連接到 Tuist 的快取、洞察和執行基礎設施。雖然你可以從[原始碼](https://github.com/tuist/tuist)編譯 Tuist，但我們建議使用以下其中一種安裝方法，以確保安裝有效且可驗證。

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> 如果你尚未安裝 Mise，請先參閱[入門指南](https://mise.jdx.dev/getting-started.html)。如果你的團隊或組織需要確保在不同環境中使用確定性的工具版本，Mise 是 [Homebrew](https://brew.sh) 的推薦替代方案。


與 Homebrew 等工具不同（後者會在全域安裝並啟用單一版本的工具），**Mise 會固定版本**，可以是全域固定或針對專案範圍固定。執行 `mise use` 以安裝並啟用 Tuist：

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

如果你複製了一個已在 `mise.toml` 中固定 Tuist 版本的專案，請執行 `mise install` 來安裝它。

> [!TIP]
> `tuist@latest` 會解析為最新的 **穩定** 版本。Tuist 也會發布預發行版（canary）和候選發布版（release candidate）；這些版本僅供選擇加入，且絕不會由 `latest` 解析。請參閱 <.localized_link href="/cli/release-channels">Release channels</.localized_link>，了解如何固定你可信賴的穩定版本線，以及如何選擇加入預發行版。

<details>
<summary>Linux 支援</summary>

在 Linux 上，Tuist 僅透過 Mise 提供。依賴 Xcode 的命令（例如 `tuist generate`）在 Linux 上不可用，但平台無關的命令（如 `tuist inspect bundle`）則可正常運作。

</details>


### <a href="https://brew.sh">Homebrew</a>（僅限 macOS）{#recommended-homebrew}

你可以使用 [Homebrew](https://brew.sh) 和 [我們的 formula](https://github.com/tuist/homebrew-tuist) 來安裝 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **驗證二進位檔的真確性**
>
> 你可以執行以下命令來驗證安裝的二進位檔是否由我們建構，該命令會檢查憑證的團隊 ID 是否為 `U6LC622NKF`：
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 代理 {#http-proxy}

如果你的網路透過 HTTP 代理路由出站流量，請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP proxy guide</.localized_link>。
