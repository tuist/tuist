---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# 安装 Tuist{#install-tuist}

Tuist CLI 包含可执行文件、动态框架及资源集（例如模板）。虽然可手动从 [源代码](https://github.com/tuist/tuist) 构建
Tuist（**），但为确保安装有效，建议采用以下安装方式之一。**

### <a href="https://github.com/jdx/mise">Mise</a>{#recommended-mise}

信息
<!-- -->
若您是需要确保不同环境下工具版本确定性的团队或组织，Mise 是替代 [Homebrew](https://brew.sh) 的推荐方案。
<!-- -->
:::

可通过以下任意命令安装 Tuist：

```bash
mise install tuist            # Install the current version specified in .tool-versions/.mise.toml
mise install tuist@x.y.z      # Install a specific version number
mise install tuist@3          # Install a fuzzy version number
```

请注意，与Homebrew等工具（全局安装并激活单一版本）不同，**Mise需通过** 命令全局或项目范围激活特定版本。具体操作如下：`mise use`:

```bash
mise use tuist@x.y.z          # Use tuist-x.y.z in the current project
mise use tuist@latest         # Use the latest tuist in the current directory
mise use -g tuist@x.y.z       # Use tuist-x.y.z as the global default
mise use -g tuist@system      # Use the system's tuist as the global default
```

### <a href="https://brew.sh">Homebrew</a>{#recommended-homebrew}

可通过[Homebrew](https://brew.sh)和[我们的公式集](https://github.com/tuist/homebrew-tuist)安装Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

::: tip VERIFYING THE AUTHENTICITY OF THE BINARIES
<!-- -->
可通过执行以下命令验证安装的二进制文件是否由我们构建：该命令将检查证书团队是否为`U6LC622NKF`:

```bash
curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
```
<!-- -->
:::
