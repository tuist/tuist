---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是为 Amp 和 Claude 等编码代理提供的持久化 Linux 和 macOS 虚拟机。每个代理会话都拥有独立的机器，在代理空闲时暂停，并在恢复时保持文件完整。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist 沙盒（包括 Linux 和 macOS）目前在我们扩展容量期间仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中联系我们，以请求为你的账户开通访问权限。当沙盒全面开放时，我们将公布定价。

沙盒是一个虚拟机，编码代理在其中运行命令并编辑文件。每个代理会话都有自己的沙盒，在会话期间保留其检出内容、构建产物和已安装的工具。当代理空闲时，沙盒会暂停；下一条消息会从上次停止的位置恢复它。

沙盒在与<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>相同的集群上运行，紧邻你团队的<.localized_link href="/guides/features/cache">缓存</.localized_link>，因此代理的构建可以使用与你的 CI 和本地机器相同的缓存制品。

你可以从以下位置使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上运行你的 Amp 工作区的 orbs，或者通过<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link>为任何 Amp 线程提供一台 Mac 用于 Xcode 构建。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上运行 Claude Managed Agents 会话和 Claude Code 云会话（claude.ai、桌面和移动应用，以及`claude --cloud`）。
- **[Tuist CLI](#cli)**：从终端或通过 API 从你自己的工具中创建沙盒并在其中运行命令。

## 开始使用 CLI {#cli}

使用`tuist sandbox`从终端创建沙盒并在其中运行命令。

### 1. 登录 {#cli-log-in}

管理沙盒需要账户管理员：

```bash
tuist auth login
```

### 2. 创建沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

对于 Linux，省略`--platform`。传递`--vcpus`和`--memory-gb`以获得更大的[规格](#platforms)，传递`--workspace-gb`以获得更大的磁盘。命令会在沙盒运行后返回并打印其详细信息，包括其 ID。它使用当前目录中 Tuist 项目的账户；传递`--account`以选择其他账户。

### 3. 运行命令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

该命令在沙盒中使用`bash -l`运行，如果沙盒已暂停，则会先恢复。`tuist`会流式传输其输出，无论运行多长时间，并以命令的状态退出；Ctrl-C 会在沙盒中取消它。根据需要传递`--cwd`、`--env NAME=VALUE`和`--timeout`（最多六小时）。

### 常见任务 {#cli-tasks}

| 任务 | 命令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 显示一个 | `tuist sandbox show <id>` |
| 暂停或恢复 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 将本地 Git 工作树的文件镜像到其中 | `tuist sandbox sync <id>` |
| 复制文件进出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 删除 | `tuist sandbox delete <id> --yes` |
| 查看使用情况 | `tuist sandbox analytics` |

添加`--json`以获取机器可读的输出。有关每个选项，请参阅<.localized_link href="/cli/sandbox">CLI 参考</.localized_link>。如果要从代码驱动沙盒，请通过[Tuist API](https://tuist.dev/api/docs)在`/api/accounts/{account_handle}/sandboxes`下使用相同的操作，或者让代理通过<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>使用它们。

无法交互式登录的工具（例如在 macOS 沙盒中构建的代理插件）可以使用具有`account:sandboxes:write`范围的<.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>进行身份验证。它可以像账户成员一样创建沙盒、在其中运行命令，以及暂停、恢复和删除它们。服务于 Amp 或 Claude 集成、分析数据和集成设置的沙盒仍由账户管理员管理。

## 从编码代理在 Mac 上构建 {#coding-agents}

在 Linux 上运行的编码代理（例如云代理会话）可以在 macOS 沙盒上构建、测试和运行 Apple 平台代码，同时继续在其运行的位置编辑文件。在 Amp 中，安装<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link>。对于其他代理，例如 Claude Code 或 Cursor：

1. 将代理连接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 服务器</.localized_link>。它的`create_sandbox`工具会告诉代理如何驱动 Mac。
2. 在代理运行的位置安装 Tuist CLI，例如在环境的设置脚本中：`mise use -g tuist@latest`，或`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（在 ARM 上使用`tuist-linux-aarch64`）。
3. 对 CLI 进行身份验证。MCP 服务器的登录不会延续到 CLI，因此要么以账户成员身份运行`tuist auth login`，要么将`TUIST_TOKEN`设置为具有`account:sandboxes:write`范围的<.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。
4. 如果环境限制网络访问，请允许`tuist.dev`。CLI 通过它将文件上传到 Mac，因此不需要其他域名。

代理为每个任务创建一台 Mac，并在每个命令之前运行`tuist sandbox sync`。它会复制 Git 未忽略的文件（无论是否已提交），之后只复制更改过的文件。然后，代理使用`tuist sandbox exec`运行诸如`xcodebuild`之类的命令，使用`tuist sandbox cp`将截图或构建的应用等结果复制回来，并在任务完成后删除 Mac。Mac 在最后一个命令结束后会继续运行 10 分钟，以便下一个命令立即启动；`tuist sandbox pause`可以更早地释放它。被遗留的 Mac 随后会暂停，并在暂停 14 天后被删除。

## Linux 和 macOS {#platforms}

**Linux** 沙盒运行 Ubuntu 24.04：

- 2 vCPU，4 GiB RAM（默认）
- 4 vCPU，8 GiB RAM
- 8 vCPU，16 GiB RAM

**macOS** 沙盒在搭载 Xcode 的 Apple Silicon 上运行：

- 8 vCPU，8 GiB RAM（默认）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

## 安全性 {#security}

- 每个沙盒都是独立的虚拟机。沙盒之间以及沙盒与 CI 作业之间不共享文件系统、内存或进程。
- 沙盒归属于某个账户，只有该账户的管理员才能管理它们。来自集成的会话只能访问该集成所连接账户的沙盒。
- 你提供给 Tuist 用于连接集成的凭据（例如 Amp 提供程序令牌或 Claude 环境密钥）会以加密方式存储，且不会再显示。
- 沙盒可以访问互联网。请像对待 CI 作业一样对待代理从沙盒中能够访问的内容。
