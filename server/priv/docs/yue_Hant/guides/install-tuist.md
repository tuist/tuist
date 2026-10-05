---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# 安裝 Tuist {#install-tuist}

Tuist 命令行介面可在 **macOS** 和 **Linux** 上運行，並將你的 Xcode、生成項目、Gradle 和 Bazel 項目連接到 Tuist 的快取、洞察和執行基礎設施。雖然你可以從[源代碼](https://github.com/tuist/tuist)構建 Tuist，但我們建議使用以下其中一種安裝方法，以確保安裝有效且可驗證。

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> \[\!NOTE\]
> 如果你尚未安裝 Mise，請先參閱[入門指南](https://mise.jdx.dev/getting-started.html)。如果你是團隊或組織，需要確保不同環境中的工具版本具確定性，Mise 是 [Homebrew](https://brew.sh) 的推薦替代方案。

與 Homebrew 等工具不同（後者會在全域安裝並啟用單一版本的工具），**Mise 會鎖定版本**，可以是全域範圍或限定於特定項目。運行 `mise use` 來安裝並啟用 Tuist：

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

如果你克隆了一個已在 `mise.toml` 中鎖定 Tuist 版本的項目，請運行 `mise install` 來安裝它。

> \[\!TIP\]
> `tuist@latest` 會解析為最新的**穩定**版本。Tuist 也會發布預發布版 Canary 和候選發布版構建；這些僅供選擇加入，且絕不會被 `latest` 解析。請參閱 \<.localized\_link href="/cli/release-channels"\>發布渠道\</.localized\_link\>，了解如何鎖定你可信賴的穩定版本線，以及如何選擇加入預發布版。

<details>
<summary>Linux support</summary>

在 Linux 上，Tuist 僅可透過 Mise 取得。依賴 Xcode 的命令（例如 `tuist generate`）在 Linux 上不可用，但平台無關的命令（如 `tuist inspect bundle`）則可正常運作。

</details>

### <a href="https://brew.sh">Homebrew</a>（僅限 macOS） {#recommended-homebrew}

你可以使用 [Homebrew](https://brew.sh) 和[我們的公式](https://github.com/tuist/homebrew-tuist) 來安裝 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> \[\!TIP\]
> **驗證二進制文件的真實性**
> 
> 你可以通過運行以下命令來驗證你的安裝二進制文件是否由我們構建，該命令會檢查證書團隊是否為 `U6LC622NKF`：
> 
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 代理 {#http-proxy}

如果你的網絡通過 HTTP 代理路由出站流量，請參閱 \<.localized\_link href="/guides/integrations/http-proxy"\>HTTP 代理指南\</.localized\_link\>。