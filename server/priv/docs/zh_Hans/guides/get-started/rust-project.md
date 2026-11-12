---
{
  "title": "Rust 项目",
  "titleTemplate": ":title · 入门指南 · 教程 · Tuist",
  "description": "将你的 Rust 项目连接到 Tuist，以跟踪构建和测试（包括文档测试），并发现不稳定测试。"
}
---
# Rust 项目 {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## 前置条件

- 一个使用 Cargo 构建的 Rust 项目。
- Tuist CLI 和 Tuist 账户。

Tuist 可与你现有的 Cargo 项目配合使用。你无需添加 Rust 依赖，也无需更改项目的构建方式。

## 连接项目

安装 <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> 和 Rust。在仪表板中创建一个项目，将其构建系统设置为 **Cargo (Rust)**。在你的仓库根目录添加 `tuist.toml`：

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

使用 `tuist auth login` 登录，然后通过 Tuist 运行你常用的 Cargo 命令。在 CI 中，使用 CI 提供商的 OIDC 身份进行认证，或将 `TUIST_TOKEN` 设置为 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。你也可以设置 `TUIST_PROJECT` 来替代添加配置文件，如果使用的是自托管服务器，还可以设置 `TUIST_URL`。

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

使用你通常传递给 Cargo 的相同参数，包括功能特性、工具链和测试过滤器。即使 Tuist 无法上传报告，Cargo 仍会保持其常规输出和退出代码。

## 继续输入 Cargo

启用 [mise 的命令包装器](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) 后，将此内容添加到 `mise.toml`：

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

添加包装器后运行 `mise reshim`。然后你可以像往常一样使用 `cargo build`、`cargo check` 和 `cargo test`。Mise 会通过 Tuist 为你运行它们。

> [!TIP] Coding agents
> 在与编码代理协作时这很有用：它们可以持续运行 `cargo build` 和 `cargo test`，而无需提醒它们添加 `tuist` 前缀。

## 编译缓存

`tuist cargo build` 会自动缓存符合条件的编译、依赖项和构建脚本运行，包括本地缓存和通过 Kura 的远程缓存。无需额外的工具或缓存配置。该缓存处于实验阶段，已在 Apple silicon Mac 上经过验证，但尚未覆盖所有编译。请参阅 <.localized_link href="/guides/features/cache/rust">Rust 缓存</.localized_link> 了解支持的编译、认证以及如何验证复用情况。

## 构建洞察

在仪表板中打开 **构建**，查看构建耗时并将本地构建与 CI 构建进行比较。选择一个构建以找出编译耗时最长的 crate，并检查其警告和错误。

编译器计时针对的是 crate，而非单个源文件。请参阅 <.localized_link href="/guides/features/build-insights/rust">Rust 构建洞察</.localized_link> 了解更多关于解读构建报告的信息。

## 测试洞察

像往常一样运行测试：

```sh
tuist cargo test --workspace
```

在仪表板中打开 **测试**，查看通过、失败和被忽略的测试，包括文档测试。Cargo 会报告套件持续时间，但稳定的 libtest 不暴露每个测试的计时。

仅运行文档测试：

```sh
tuist cargo test --doc
```

在 <.localized_link href="/guides/features/test-insights/rust">Rust 测试洞察</.localized_link> 和 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust 不稳定测试</.localized_link> 中阅读更多内容。
