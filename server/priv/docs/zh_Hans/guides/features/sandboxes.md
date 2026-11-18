---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是供 Amp 和 Claude 等编码智能体使用的持久化 Linux 和 macOS 虚拟机。每个智能体会话拥有独立的机器，在智能体空闲时暂停运行，并在恢复时保持文件完整。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **仅限邀请**
>
> 在我们扩容期间，Tuist 沙盒（Linux 和 macOS）目前仅限受邀用户使用。[联系我们](mailto:contact@tuist.dev)或在 [社区 Slack](https://slack.tuist.dev) 中留言，为你的账户申请访问权限。当沙盒全面开放时，我们将公布定价。

沙盒是一个虚拟机，编码代理在其中运行命令并编辑文件。每个代理会话都拥有自己的沙盒，在会话存续期间保留其代码检出、构建产物和已安装的工具。当代理空闲时，沙盒会暂停；下一条消息会从上次停止的位置恢复执行。

沙盒与 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 运行在同一集群上，并与你团队的 <.localized_link href="/guides/features/cache">缓存</.localized_link> 相邻，因此代理的构建可以使用与你的 CI 和本地机器相同的缓存构件。

你可以通过以下方式沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上运行你的 Amp 工作区中的 orbs。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上运行 Claude Managed Agents 会话和 Claude Code 云会话（claude.ai、桌面和移动应用，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：从终端或通过 API 从你自己的工具创建沙盒并在其中运行命令。

## 使用 CLI 入门 {#cli}

使用 `tuist sandbox` 从终端创建沙盒并在其中运行命令。

### 1. 登录 {#cli-log-in}

管理沙盒需要账户管理员：

```bash
tuist auth login
```

### 2. 创建沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

对于 Linux，省略 `--platform`。传递 `--vcpus` 和 `--memory-gb` 以获得更大的 [规格](#platforms)，传递 `--workspace-gb` 以获得更大的磁盘空间。一旦沙盒开始运行，该命令就会返回并打印其详细信息，包括其 ID。它使用当前目录中 Tuist 项目的账户；传递 `--account` 以选择其他账户。

### 3. 运行命令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

该命令在沙盒中使用 `bash -lc` 运行，如果沙盒处于暂停状态则会先恢复，并且 `tuist` 会以命令的状态退出。

### 常见任务 {#cli-tasks}

| 任务 | 命令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 显示单个沙盒 | `tuist sandbox show <id>` |
| 暂停或恢复 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 删除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

添加 `--json` 以获取机器可读的输出。有关所有选项，请参阅 <.localized_link href="/cli/sandbox">CLI 参考</.localized_link>。如果要从代码驱动沙盒，请通过 [Tuist API](https://tuist.dev/api/docs) 下的 `/api/accounts/{account_handle}/sandboxes` 使用相同的操作，或者让代理通过 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> 使用它们。

## Linux 和 macOS {#platforms}

**Linux** 沙盒运行 Ubuntu 24.04：

- 2 vCPU，4 GiB RAM（默认）
- 4 vCPU，8 GiB RAM
- 8 vCPU，16 GiB RAM

**macOS** 沙盒在搭载 Xcode 的 Apple silicon 上运行：

- 8 vCPU，8 GiB RAM（默认）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

## 安全性 {#security}

- 每个沙盒都是独立的虚拟机。沙盒彼此之间以及与 CI 作业之间不共享文件系统、内存或进程。
- 沙盒归属于某个账户，只有该账户的管理员可以管理它们。来自集成的会话只能访问该集成所连接账户的沙盒。
- 你提供给 Tuist 用于连接集成的凭据（例如 Amp 提供商令牌或 Claude 环境密钥）会以加密方式存储，且不会再显示。
- 沙盒可以访问互联网。请以对待 CI 作业的方式对待代理从沙盒中可以访问的内容。
