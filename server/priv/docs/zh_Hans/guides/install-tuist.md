---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Install the Tuist command-line interface on macOS or Linux with mise or Homebrew, and pin a version for teams and continuous integration."
}
---
# 安装 Tuist {#install-tuist}

Tuist 命令行界面运行于 **macOS** 和 **Linux**，并将你的 Xcode、生成项目、Gradle 和 Bazel 项目连接到 Tuist 的缓存、洞察和运行器基础设施。虽然你可以从[源代码](https://github.com/tuist/tuist)构建 Tuist，但我们建议使用以下安装方法之一，以确保安装有效且可验证。

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> 如果你尚未安装 Mise，请先参阅[入门指南](https://mise.jdx.dev/getting-started.html)。如果你的团队或组织需要确保不同环境中工具版本的确定性，Mise 是[Homebrew](https://brew.sh)的推荐替代方案。


与 Homebrew 等工具不同（后者在全局范围内安装并激活单一版本的工具），**Mise 会固定版本**，可以是全局固定，也可以限定在项目范围内。运行 `mise use` 以安装并激活 Tuist：

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

如果你克隆的项目已在 `mise.toml` 中固定了 Tuist 版本，请运行 `mise install` 进行安装。

> [!TIP]
> `tuist@latest` 解析为最新的**稳定**版本。Tuist 还会发布预发布的 Canary 和候选发布版本；这些版本仅在选择加入时可用，且永远不会由 `latest` 解析。请参阅<.localized_link href="/cli/release-channels">发布渠道</.localized_link>，了解如何固定你可信赖的稳定版本线，以及如何选择加入预发布版本。

<details>
<summary>Linux 支持</summary>

在 Linux 上，Tuist 仅通过 Mise 提供。依赖于 Xcode 的命令（例如 `tuist generate`）在 Linux 上不可用，但平台无关的命令（如 `tuist inspect bundle`）可以正常工作。

</details>


### <a href="https://brew.sh">Homebrew</a>（仅限 macOS）{#recommended-homebrew}

你可以使用 [Homebrew](https://brew.sh) 和 [我们的公式](https://github.com/tuist/homebrew-tuist) 来安装 Tuist：

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **验证二进制文件的真实性**
>
> 你可以运行以下命令来验证你安装的二进制文件是否由我们构建，该命令会检查证书的 Team ID 是否为 `U6LC622NKF`：
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP 代理 {#http-proxy}

如果你的网络通过 HTTP 代理路由出站流量，请参阅<.localized_link href="/guides/integrations/http-proxy">HTTP 代理指南</.localized_link>。
