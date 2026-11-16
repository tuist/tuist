---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是为 Amp 和 Claude 等编码智能体提供的持久化 Linux 和 macOS 虚拟机。每个智能体会话拥有独立的机器，在智能体空闲时暂停运行，并在恢复时保持文件完整。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前在我们扩展容量期间仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言，以请求为你的账户开通访问权限。当沙盒全面开放时，我们将公布定价。

沙盒是一个虚拟机，编码代理在其中运行命令并编辑文件。每个代理会话都有专属的沙盒，在会话生命周期内保留其代码检出、构建产物和已安装的工具。当代理处于空闲状态时，沙盒会暂停；下一条消息将使其从上次中断处恢复。

沙盒与<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>运行在同一集群上，紧邻你团队的<.localized_link href="/guides/features/cache">缓存</.localized_link>，因此代理的构建可以使用与你的 CI 和本地机器相同的缓存构件。

你可以通过以下方式使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上运行你的 Amp 工作区中的 orbs，或通过<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link>为任何 Amp 线程提供用于 Xcode 构建的 Mac。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上运行 Claude Managed Agents 会话和 Claude Code 云会话（claude.ai、桌面和移动应用，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：从终端或通过 API 从你自己的工具中创建沙盒并在其中运行命令。

## 通过 CLI 入门 {#cli}

使用 `tuist sandbox` 从终端创建沙盒并在其中运行命令。

### 1. 登录 {#cli-log-in}

管理沙盒需要账户管理员权限：

```bash
tuist auth login
```

### 2. 创建沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

对于 Linux，省略 `--platform`。传递 `--vcpus` 和 `--memory-gb` 以获得更大的[规格](#platforms)，传递 `--workspace-gb` 以获得更大的磁盘。命令会在沙盒运行后返回并打印其详细信息，包括 ID。它使用当前目录中 Tuist 项目的账户；传递 `--account` 以选择其他账户。

### 3. 运行命令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

该命令在沙盒中使用 `bash -l` 运行，如果沙盒已暂停，则会先恢复。`tuist` 会流式输出其运行结果，并在命令结束时退出；在沙盒中按 Ctrl-C 可取消命令。根据需要传递 `--cwd`、`--env NAME=VALUE` 和 `--timeout`（最长六小时）。

### 常见任务 {#cli-tasks}

| 任务 | 命令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 显示单个沙盒 | `tuist sandbox show <id>` |
| 暂停或恢复 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 将本地 Git 工作树的文件镜像到沙盒中 | `tuist sandbox sync <id>` |
| 复制文件进出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 删除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

添加 `--json` 以获取机器可读的输出。查看<.localized_link href="/cli/sandbox">CLI 参考</.localized_link>了解所有选项。若要通过代码驱动沙盒，请通过[Tuist API](https://tuist.dev/api/docs)在 `/api/accounts/{account_handle}/sandboxes` 下执行相同操作，或让代理通过<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>使用它们。

无法进行交互式登录的工具（例如在 macOS 沙盒中构建的代理插件）可以改用具有 `account:sandboxes:write` 范围的<.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>进行身份验证。它可以像账户成员一样创建沙盒、在其中运行命令，以及暂停、恢复和删除沙盒。服务于 Amp 或 Claude 集成、分析数据和集成设置的沙盒仍由账户管理员管理。

### 沙盒内的 Tuist {#tuist-in-sandbox}

沙盒镜像不包含 Tuist CLI，因此运行的是你项目自身锁定的版本。在第一次 `tuist sandbox sync` 后，在沙盒中的仓库根目录运行 `mise install`（已安装 `mise` 和 `brew`），然后通过 mise 运行 `tuist`，例如将 `$HOME/.local/share/mise/shims` 添加到 `PATH`。

你使用 `tuist sandbox exec` 启动的每个命令都会获得与 Tuist runner 相同的配置，因此沙盒中的构建可以使用你账户的<.localized_link href="/guides/features/cache">缓存</.localized_link>，而无需你传递凭据：

- `TUIST_URL`，以及在沙盒主机可以访问的情况下（例如在 macOS 上），同一机架中缓存的 `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，一个用于该命令的短期身份令牌。Tuist CLI 4.218.0 及更高版本会自动使用它登录；对于 4.215.0 到 4.217.x 版本，请在同一命令中先运行 `tuist auth login`。

令牌是为每个命令生成的，只能在该命令运行时交换为 Tuist 令牌，因此沙盒永远不会持有长期有效的凭据。它授予的权限不会超过启动命令的人员或令牌对缓存所拥有的权限：如果账户的缓存仅允许令牌写入，则成员将获得读取权限；并且账户令牌需要缓存范围（例如 `ci`）以及 `account:sandboxes:write`，沙盒才能使用缓存。你通过 `--env` 传递的变量具有优先权。

## 从编码代理在 Mac 上构建 {#coding-agents}

在 Linux 上运行的编码代理（例如云代理会话）可以在 macOS 沙盒上构建、测试和运行 Apple 平台代码，同时继续在其运行位置编辑文件。在 Amp 中，安装<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link>。对于其他代理（例如 Claude Code 或 Cursor）：

1. 将代理连接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 服务器</.localized_link>。它的 `create_sandbox` 工具会告知代理如何驱动 Mac。
2. 在代理运行的位置安装 Tuist CLI，例如在环境的设置脚本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 上使用 `tuist-linux-aarch64`）。
3. 对 CLI 进行身份验证。MCP 服务器的登录状态不会传递给它，因此要么以账户成员身份运行 `tuist auth login`，要么将 `TUIST_TOKEN` 设置为具有 `account:sandboxes:write` 范围的<.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。
4. 如果环境限制了网络访问，请允许 `tuist.dev`。CLI 通过它向 Mac 上传文件，因此不需要其他域名。

代理为每个任务创建一个 Mac，并在执行每个命令之前运行 `tuist sandbox sync`。它会复制 Git 未忽略的文件（无论是否已提交），之后仅复制发生变化的文件。首次同步后，它会在 Mac 上的仓库根目录运行 `mise install`，以便[项目锁定的 Tuist](#tuist-in-sandbox)就位并登录到你的账户缓存。然后，代理使用 `tuist sandbox exec` 运行诸如 `xcodebuild` 之类的命令，使用 `tuist sandbox cp` 将截图或构建的应用等结果复制回来，并在任务完成后删除 Mac。Mac 在最后一个命令执行后会保持运行 10 分钟，以便下一个命令立即启动；`tuist sandbox pause` 可以更早地释放它。被遗留的 Mac 随后会暂停，并在暂停 14 天后被删除。

## Linux 和 macOS {#platforms}

**Linux** 沙盒运行 Ubuntu 24.04：

- 2 vCPU，4 GiB RAM（默认）
- 4 vCPU，8 GiB RAM
- 8 vCPU，16 GiB RAM

**macOS** 沙盒在配备 Xcode 的 Apple silicon 上运行：

- 8 vCPU，8 GiB RAM（默认）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

## 安全性 {#security}

- 每个沙盒都是独立的虚拟机。沙盒之间以及沙盒与 CI 作业之间不共享文件系统、内存或进程。
- 沙盒归属于某个账户，只有该账户的管理员才能管理它们。来自集成的会话只能访问该集成所连接账户的沙盒。
- 你提供给 Tuist 用于连接集成的凭据（例如 Amp 提供商令牌或 Claude 环境密钥）会以加密方式存储，且不会再显示。
- 沙盒可以访问互联网。请以对待 CI 作业的方式对待代理从沙盒中能够访问的内容。
