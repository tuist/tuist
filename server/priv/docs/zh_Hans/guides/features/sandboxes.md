---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是专为 Amp 和 Claude 等编码智能体设计的持久化 Linux 与 macOS 虚拟机。每个智能体会话独占一台机器，在空闲时自动暂停，并在恢复时保持文件完整无损。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist 沙盒（包括 Linux 和 macOS）目前处于扩容阶段，仅限受邀用户访问。[联系我们](mailto:contact@tuist.dev)或在 [社区 Slack](https://slack.tuist.dev) 中留言，为你的账户申请访问权限。待沙盒全面开放时，我们将公布定价。

沙盒是一台虚拟机，编程代理在其中运行命令并编辑文件。每个代理会话都有独立的沙盒，在会话期间保留其代码检出、构建产物和已安装的工具。当代理空闲时，沙盒会暂停；下一条消息会从中断处恢复执行。

沙盒与 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 运行在同一集群上，紧邻你团队的 <.localized_link href="/guides/features/cache">缓存</.localized_link>，因此代理的构建可以像你的 CI 和本地机器一样使用相同的缓存制品。

你可以从以下途径使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上运行 Amp 工作区的 orbs，或通过 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link> 为任何 Amp 线程提供用于 Xcode 构建的 Mac。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上运行 Claude Managed Agents 会话和 Claude Code 云会话（claude.ai、桌面和移动应用，以及 `claude --cloud`）。
- **[Tuist CLI](#cli)**：从终端创建沙盒并在其中运行命令，或通过 API 从你自己的工具中进行操作。

## 开始使用 CLI {#cli}

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

对于 Linux，省略 `--platform`。传递 `--xcode` 并指定版本，例如 `--xcode 26.1.1`，以获取带有该 [Xcode](#xcode) 的 Mac；这隐含了 `--platform macos`。传递 `--vcpus` 和 `--memory-gb` 以获得更大的 [规格](#platforms)，传递 `--workspace-gb` 以获得更大的磁盘。沙盒运行后命令才会返回，并打印其详细信息，包括 ID。它使用当前目录下 Tuist 项目的账户；传递 `--account` 可选择其他账户。

### 3. 运行命令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

该命令在沙盒中通过 `bash -l` 运行，如果沙盒处于暂停状态则会先恢复。`tuist` 会流式输出其结果，无论运行多久，并以命令的状态退出；Ctrl-C 可在沙盒中取消该命令。根据需要传递 `--cwd`、`--env NAME=VALUE` 和 `--timeout`（最长六小时）。

### 常见任务 {#cli-tasks}

| 任务 | 命令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 显示单个沙盒 | `tuist sandbox show <id>` |
| 暂停或恢复 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 将本地 Git 工作树的文件镜像到沙盒中 | `tuist sandbox sync <id>` |
| 复制文件进出沙盒 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 删除 | `tuist sandbox delete <id> --yes` |
| 查看用量 | `tuist sandbox analytics` |

添加 `--json` 以获取机器可读的输出。查看所有选项请参考 <.localized_link href="/cli/sandbox">CLI 参考文档</.localized_link>。若要从代码中驱动沙盒，可通过 [Tuist API](https://tuist.dev/api/docs) 在 `/api/accounts/{account_handle}/sandboxes` 下执行相同操作，或让代理通过 <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> 使用它们。

无法进行交互式登录的工具（例如在 macOS 沙盒中构建的代理插件），可以使用具有 `account:sandboxes:write` 范围的 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link> 进行身份验证。它可以像账户成员一样创建沙盒、在其中运行命令，以及暂停、恢复和删除沙盒。服务于 Amp 或 Claude 集成、分析数据和集成设置的沙盒仍由账户管理员管理。

### 沙盒内的 Tuist {#tuist-in-sandbox}

沙盒镜像不包含 Tuist CLI，因此运行的是你项目自身锁定的版本。首次 `tuist sandbox sync` 后，在沙盒中的仓库根目录运行 `mise install`（已安装 `mise` 和 `brew`），然后通过 mise 运行 `tuist`，例如将 `$HOME/.local/share/mise/shims` 加入 `PATH`。

你通过 `tuist sandbox exec` 启动的每个命令都会获得与 Tuist runner 相同的配置，因此沙盒中的构建可以使用你账户的 <.localized_link href="/guides/features/cache">缓存</.localized_link>，而无需你传递凭据：

- `TUIST_URL`，以及在沙盒主机可达的情况下（例如在 macOS 上），同一机架中缓存的 `TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，这是该命令的短期身份令牌。Tuist CLI 4.218.0 及更高版本会自动使用它登录；对于 4.215.0 到 4.217.x 版本，需在同一命令中先运行 `tuist auth login`。

令牌为每个命令单独生成，仅在该命令运行期间可交换为 Tuist 令牌，因此沙盒永远不会持有长期凭据。它授予的权限绝不会超过启动命令的人员或令牌对缓存所拥有的权限：如果账户的缓存令牌仅具有写入权限，则其成员将获得读取权限；要使沙盒使用缓存，账户令牌除了需要 `account:sandboxes:write` 外，还需要缓存范围，例如 `ci`。通过 `--env` 传递的变量具有更高优先级。

## 从编程代理在 Mac 上构建 {#coding-agents}

在 Linux 上运行的编程代理（例如云代理会话）可以在 macOS 沙盒上构建、测试和运行 Apple 平台代码，同时继续在其运行位置编辑文件。在 Amp 中，安装 <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link>。对于其他代理，例如 Claude Code 或 Cursor：

1. 将代理连接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 服务器</.localized_link>。其 `create_sandbox` 工具会告知代理如何驱动 Mac。
2. 在代理运行的位置安装 Tuist CLI，例如在环境设置脚本中：`mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 架构使用 `tuist-linux-aarch64`）。
3. 对 CLI 进行身份验证。MCP 服务器的登录状态不会延续到 CLI，因此要么以账户成员身份运行 `tuist auth login`，要么将 `TUIST_TOKEN` 设置为具有 `account:sandboxes:write` 范围的 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。
4. 如果环境限制网络访问，请允许 `tuist.dev`。CLI 通过它向 Mac 上传文件，因此不需要其他域名。

代理为每个任务创建一个 Mac，并使用项目锁定的 [Xcode](#xcode)：`create_sandbox` 列出可供选择的 Xcode 版本，并告知代理读取项目的锁定配置，例如 `.xcode-version`。在执行每个命令之前，它会运行 `tuist sandbox sync`。它会复制 Git 未忽略的文件（无论是否已提交），之后仅复制发生更改的文件。首次同步后，它会在 Mac 上的仓库根目录运行 `mise install`，从而确保 [项目锁定的 Tuist](#tuist-in-sandbox) 就位，并已登录到你账户的缓存。随后，代理通过 `tuist sandbox exec` 运行诸如 `xcodebuild` 之类的命令，使用 `tuist sandbox cp` 将截图或构建好的应用等结果复制回来，并在任务完成后删除 Mac。Mac 在最后一个命令执行完毕后保持运行 10 分钟，以便下一个命令立即启动；`tuist sandbox pause` 可以更快地释放它。被遗留的 Mac 会暂停，并在暂停 14 天后被删除。

## Linux 和 macOS {#platforms}

**Linux** 沙盒运行 Ubuntu 24.04：

- 2 vCPU，4 GiB RAM（默认）
- 4 vCPU，8 GiB RAM
- 8 vCPU，16 GiB RAM

**macOS** 沙盒在配备 Xcode 的 Apple silicon 上运行：

- 8 vCPU，8 GiB RAM（默认）
- 8 vCPU，16 GiB RAM
- 8 vCPU，24 GiB RAM

### 选择 Xcode {#xcode}

每个 macOS 沙盒运行一个 Xcode，你在创建时进行选择。它启动的镜像与针对该 Xcode 的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 配置文件相同，因此代理使用的工具链和模拟器与你的 CI 一致。在 tuist.dev 上，macOS 沙盒目前提供：

- `26.6`（默认）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

使用 `xcode_version`（CLI 中为 `--xcode`）选择一个，需使用确切版本，如同 runner 配置文件那样：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 和 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| 适用于 Amp 的 Tuist Mac 插件 | `tuist_mac_start` 搭配 `xcode` |
| Amp orbs | orb 类型 `macos-xcode-26-1-1`（参见 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 和 Claude Managed Agents | 环境上的 `xcode_version`，或每个 Managed Agents 会话（参见 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **如果不指定版本**，Mac 将获得默认版本。
- **如果请求的版本 Tuist 不提供，则会被拒绝**，错误信息会列出你可选择的版本，以便你了解当前可用的选项。
- **Tuist 不会读取你仓库中的 `.xcode-version`。** 由你或请求 Mac 的代理来选择版本。MCP 工具和 Tuist Mac 插件会告知代理匹配项目锁定的版本。
- **沙盒在其生命周期内保留其 Xcode。** 若要使用其他 Xcode 进行构建，请创建一个新的沙盒。`xcodebuild -version` 显示 Mac 正在运行的 Xcode 版本。

## 安全性 {#security}

- 每个沙盒都是独立的虚拟机。沙盒之间以及沙盒与 CI 作业之间不共享文件系统、内存或进程。
- 沙盒归属于某个账户，只有该账户的管理员才能管理它们。来自集成的会话只能访问该集成所连接账户的沙盒。
- 你提供给 Tuist 用于连接集成的凭据（例如 Amp 提供商令牌或 Claude 环境密钥）会以加密方式存储，且不会再显示。
- 沙盒可以访问互联网。请以对待 CI 作业的方式对待代理从沙盒中能够访问的内容。
