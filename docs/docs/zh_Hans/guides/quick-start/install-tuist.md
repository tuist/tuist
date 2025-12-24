---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 安装图易斯特{#install-tuist}

Tuist CLI
由可执行文件、动态框架和一组资源（例如模板）组成。尽管您可以从[源代码](https://github.com/tuist/tuist)手动构建
Tuist，**，但我们建议您使用以下安装方法之一，以确保安装有效。**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

::: info
<!-- -->
如果你是一个团队或组织，需要确保不同环境下工具版本的确定性，那么 Mise 是[Homebrew](https://brew.sh)的推荐替代方案。
<!-- -->
:::

您可以通过以下任意命令安装 Tuist：

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

请注意，与 Homebrew 等在全局范围内安装和激活单个版本的工具不同，**Mise 需要在全局范围内或在项目范围内激活一个版本**
。具体方法是运行`mise use` ：

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a> {#recommended-homebrew}

您可以使用 [自制程序](https://brew.sh)和
[我们的公式](https://github.com/tuist/homebrew-tuist)安装 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
<!-- -->
您可以运行以下命令来验证您的安装二进制文件是否已由我们构建，该命令将检查证书团队是否为`U6LC622NKF` ：

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
