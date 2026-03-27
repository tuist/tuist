---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 安裝 Tuist{#install-tuist}

Tuist CLI 由一個可執行檔，動態框架和一套資源（例如模板）組成。雖然您可以從
[原始碼](https://github.com/tuist/tuist)手動建立 Tuist，**，但我們建議您使用下列其中一種安裝方法，以確保安裝有效。**

### <a href="https://github.com/jdx/mise">Mise</a>{#recommended-mise}

::: info
<!-- -->
如果您的團隊或組織需要確保工具在不同環境下的版本是確定的，Mise 是 [Homebrew](https://brew.sh) 的建議替代方案。
<!-- -->
:::

您可以透過下列任何一種指令安裝 Tuist：

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

請注意，不像 Homebrew 之類的工具，會在全局安裝並啟用單一版本的工具，**Mise 需要啟用**
的版本，可以是全局版本，也可以是專案範圍內的版本。執行`mise use` 即可：

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

您可以使用 [Homebrew](https://brew.sh) 和
[我們的公式](https://github.com/tuist/homebrew-tuist) 安裝 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
<!-- -->
您可以執行下列指令來驗證您安裝的二進位檔案是否已由我們建立，該指令會檢查證書的團隊是否為`U6LC622NKF` ：

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
