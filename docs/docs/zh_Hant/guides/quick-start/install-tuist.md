---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 安裝 Tuist{#install-tuist}

**Tuist CLI 包含可執行檔、動態框架及一組資源（例如範本）。雖然您可手動從原始碼編譯 Tuist，但我們建議採用以下安裝方式之一以確保安裝有效：**

### <a href="https://github.com/jdx/mise">Mise</a>{#recommended-mise}

::: info
<!-- -->
若您所屬的團隊或組織需要確保工具在不同環境中具有確定性版本，Mise 是取代 [Homebrew](https://brew.sh) 的推薦替代方案。
<!-- -->
:::

您可透過以下任一指令安裝 Tuist：

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

請注意，與 Homebrew 等工具不同，後端工具（**）的 Mise 需透過** 啟用特定版本，可選擇全域啟用或限定於專案範圍。操作方式如下：`mise
use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a>{#recommended-homebrew}

您可透過 [Homebrew](https://brew.sh) 與
[我們的公式集](https://github.com/tuist/homebrew-tuist) 安裝 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
<!-- -->
您可執行以下指令驗證安裝的二進位檔是否由我們編譯：此指令將檢查憑證團隊是否為`U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
