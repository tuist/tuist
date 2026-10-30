---
{
  "title": "安裝 Tuist",
  "titleTemplate": ":title · 指南 · Tuist",
  "description": "使用 mise 或 Homebrew 在 macOS 或 Linux 上安裝 Tuist 命令列介面，並為團隊和持續整合固定版本。"
}
---
# 安裝 Tuist {#install-tuist}

Tuist 命令行介面喺 **macOS** 同 **Linux** 上運行，並将你嘅 Xcode、生成項目、Gradle 同 Bazel 項目連接到 Tuist 嘅快取、洞察同 runner 基礎設施。雖然你可以從[原始碼](https://github.com/tuist/tuist)編譯 Tuist，但我哋建議使用以下其中一種安裝方法，以確保安裝有效且可驗證。

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> 如果你未安裝 Mise，請先參閱[入門指南](https://mise.jdx.dev/getting-started.html)。如果你係一個需要確保工具喺唔同環境中版本一致嘅團隊或組織，Mise 係 [Homebrew](https://brew.sh) 嘅推薦替代方案。


同 Homebrew 等工具唔同（Homebrew 會全局安裝並啟用單一版本），**Mise 可以鎖定版本**，無論係全局定係針對特定項目。運行 `mise use` 來安裝並啟用 Tuist：

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

如果你克隆咗一個已經喺 `mise.toml` 中鎖定咗 Tuist 版本嘅項目，請運行 `mise install` 來安裝佢。

> [!TIP]
> `tuist@latest` 會解析為最新嘅 **穩定** 版本。Tuist 亦會發布預發布嘅 canary 同候選版本；呢啲版本需要手動選擇，並且永遠唔會被 `latest` 解析。請參閱 <.localized_link href="/cli/release-channels">Release channels</.localized_link> 了解如何鎖定你可以信任嘅穩定版本線，以及如何選擇加入預發布版本。

<details>
<summary>Linux 支援</summary>

喺 Linux 上，Tuist 僅透過 Mise 提供。依賴 Xcode 嘅命令（例如 `tuist generate`）喺 Linux 上不可用，但平台無關嘅命令如 `tuist inspect bundle` 則可以正常運作。

</details>


### <a href="https://brew.sh">Homebrew</a>（僅限 macOS）{#recommended-homebrew}

你可以使用 [Homebrew](https://brew.sh) 同 [我哋嘅 formula](https://github.com/tuist/homebrew-tuist) 來安裝 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **驗證二進制文件嘅真實性**
>
> 你可以通過運行以下命令來驗證你安裝嘅二進制文件係由我哋構建嘅，該命令會檢查證書團隊是否為 `U6LC622NKF`：
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 代理 {#http-proxy}

如果你嘅網絡通過 HTTP 代理路由出站流量，請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理指南</.localized_link>。
