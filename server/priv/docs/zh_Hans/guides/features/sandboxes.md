---
{
  "title": "沙盒",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "Tuist 沙盒是专为 Amp 和 Claude 等编码智能体设计的持久化 Linux 和 macOS 虚拟机。每个智能体会话都拥有独立的机器，在智能体闲置时暂停，并在恢复时保持文件完整。"
}
---
# 沙盒 {#sandboxes}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist 沙盒（Linux 和 macOS）目前处于仅限邀请阶段，我们正在扩展容量。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中联系我们，为你的账户申请访问权限。当沙盒全面开放时，我们将公布定价。

沙盒是一个虚拟机，编码代理在其中运行命令并编辑文件。每个代理会话都有独立的沙盒，在会话期间保留其代码检出、构建产物和已安装的工具。当代理空闲时，沙盒会暂停；下一条消息会从暂停处恢复执行。

沙盒与<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>运行在同一集群上，紧邻你团队的<.localized_link href="/guides/features/cache">缓存</.localized_link>，因此代理的构建可以使用与你的 CI 和本地机器相同的缓存制品。

你可以从以下位置使用沙盒：

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**：在 Tuist 上运行你的 Amp 工作区 orbs，或通过<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link>为任何 Amp 线程提供用于 Xcode 构建的 Mac。
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**：在 Tuist 上运行 Claude Managed Agents 会话和 Claude Code 云会话（claude.ai、桌面和移动应用，以及`claude --cloud`）。
- **[Tuist CLI](#cli)**：从终端或通过 API 从你自己的工具中创建沙盒并在其中运行命令。

## 通过 CLI 开始使用 {#cli}

使用`tuist sandbox`从终端创建沙盒并在其中运行命令。

### 1. 登录 {#cli-log-in}

账户的任何成员都可以创建和管理其沙盒：

```bash
tuist auth login
```

### 2. 创建沙盒 {#cli-create}

```bash
tuist sandbox create --platform macos
```

对于 Linux，省略`--platform`。传递带有版本的`--xcode`（例如`--xcode 26.1.1`），以获取具有该[Xcode](#xcode)的 Mac；这隐含了`--platform macos`。传递`--vcpus`和`--memory-gb`以获得更大的[规格](#platforms)，传递`--guaranteed-vcpus`以保证 Linux 沙盒拥有更多[CPU](#guaranteed-cpu)，传递`--workspace-gb`以获得更大的磁盘。沙盒从创建时起运行两小时，每次恢复后再次运行两小时；传递`--lifetime-minutes`可设置为 5 分钟到一天之间的时长。当生命周期结束时，正在运行的命令会被取消，沙盒会暂停并归档，保留其文件，因此被遗忘的沙盒将停止占用你账户的容量。一旦沙盒开始运行，命令就会返回并打印其详细信息，包括其 ID。它使用当前目录中 Tuist 项目的账户；传递`--account`可选择其他账户。

### 3. 运行命令 {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

该命令在沙盒中使用`bash -l`运行，如果沙盒处于暂停状态，会先恢复。`tuist`会流式传输其输出，无论运行多长时间，并以命令的状态退出；Ctrl-C 可在沙盒中取消它。根据需要传递`--cwd`、`--env NAME=VALUE`和`--timeout`（最长六小时）。

该命令与`tuist`分离运行，因此即使连接断开也能继续执行。为了将长时间构建适应有时限的工具调用（例如代理的调用），请传递`--wait <seconds>`：当超时时，`tuist`会让命令继续运行，以状态码 75 退出，并打印`tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …`命令，该命令将从停止处继续输出并以命令的状态退出。

### 常见任务 {#cli-tasks}

| 任务 | 命令 |
| --- | --- |
| 列出沙盒 | `tuist sandbox list` |
| 显示单个沙盒 | `tuist sandbox show <id>` |
| 暂停或恢复 | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| 延长运行时间超过过期时间 | `tuist sandbox extend <id> --lifetime-minutes 240` |
| 将本地 Git 工作树的文件镜像到沙盒中 | `tuist sandbox sync <id>` |
| 复制文件进出 | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| 删除 | `tuist sandbox delete <id> --yes` |
| 查看使用情况 | `tuist sandbox analytics` |

添加`--json`以获取机器可读的输出。查看<.localized_link href="/cli/sandbox">CLI 参考</.localized_link>了解所有选项。如果要从代码驱动沙盒，请通过[Tuist API](https://tuist.dev/api/docs)在`/api/accounts/{account_handle}/sandboxes`下使用相同的操作，或让代理通过<.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>使用它们。

无法交互式登录的工具（例如在 macOS 沙盒中构建的代理插件）可以使用具有`account:sandboxes:write`范围的<.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>进行身份验证。它可以执行账户成员可以做的操作：创建沙盒、在其中运行命令，以及暂停、恢复、归档和删除沙盒。集成设置以及在服务于集成的沙盒中运行命令的权限保留给账户管理员。

### 沙盒中的 Tuist {#tuist-in-sandbox}

macOS 沙盒预装了 Tuist CLI。当你的项目通过 mise（`mise.toml`或`.tool-versions`）固定 Tuist 版本时，`tuist`会运行该版本，该版本在命令首次需要时安装。你使用`tuist sandbox exec`启动的每个命令都将 mise 的 shim（`$HOME/.local/share/mise/shims`）放在`PATH`的最前面，并将镜像中的 Tuist 放在最后，因此`tuist`和你的其他 mise 工具会在你的命令以及 Xcode 构建阶段（例如 scheme 的 post-actions）中运行。每台 Mac 还在`/opt/tuist/agent-guide.md`处携带了一份面向编码代理的指南，该指南从其镜像生成：包括其 Xcode 和模拟器、仓库位置以及就绪快照包含的内容。在 Mac 上运行的 Claude Code、Codex 和 Amp 会通过其指令文件找到该指南。

你使用`tuist sandbox exec`启动的每个命令还会获得 Tuist runner 所拥有的功能，因此沙盒中的构建可以使用你账户的<.localized_link href="/guides/features/cache">缓存</.localized_link>，而无需你传递凭据：

- `TUIST_URL`，以及在沙盒主机可以访问的位置（例如 macOS 上），同一机架中缓存的`TUIST_CACHE_ENDPOINT`。
- `TUIST_OIDC_TOKEN`，这是针对该命令的短期身份令牌。Tuist CLI 4.218.0 及更高版本会自动使用它登录；对于 4.215.0 到 4.217.x 版本，请在同一命令中先运行`tuist auth login`。

令牌是为每个命令生成的，只能在该命令运行时交换为 Tuist 令牌，因此沙盒永远不会持有长期凭据。它授予的权限不会超过启动命令的人员或令牌对缓存所能执行的权限：账户成员的缓存令牌如果只能写入，则获得读取访问权限；账户令牌需要缓存范围（例如`ci`）以及`account:sandboxes:write`，沙盒才能使用缓存。你通过`--env`传递的变量具有优先权。

## 从编码代理在 Mac 上构建 {#coding-agents}

在 Linux 上运行的编码代理（例如云代理会话）可以在 macOS 沙盒上构建、测试和运行 Apple 平台代码，同时在其运行位置继续编辑文件。在 Amp 中，安装<.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac 插件</.localized_link>。对于其他代理（例如 Claude Code 或 Cursor）：

1. 将代理连接到 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 服务器</.localized_link>。其`create_sandbox`工具会告知代理如何驱动 Mac。
2. 在代理运行的位置安装 Tuist CLI，例如在环境的设置脚本中：`mise use -g tuist@latest`，或者 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`（ARM 架构上使用 `tuist-linux-aarch64`）。
3. 对 CLI 进行身份验证。MCP 服务器的登录状态不会延续到 CLI，因此要么以账户成员身份运行 `tuist auth login`，要么将 `TUIST_TOKEN` 设置为具有 `account:sandboxes:write` 范围的<.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。
4. 如果环境限制网络访问，请允许访问 `tuist.dev`。CLI 通过它向 Mac 上传文件，因此不需要其他域名。
5. （可选）允许代理无需每次询问即可创建和删除 Mac。代理在调用 `create_sandbox` 之前会询问，因为 Mac 计入你账户的限制；在调用 `delete_sandbox` 之前也会询问，因为该操作无法撤销。在 Claude Code 中，在 `.claude/settings.json` 中允许这两项操作，使用你注册 MCP 服务器时使用的名称（此处为 `tuist`）：

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

要让代理执行设置，请提供以下提示：

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

代理为每个任务创建一个 Mac，并使用项目锁定的 [Xcode](#xcode)：`create_sandbox` 列出可供选择的 Xcode 版本，并告知代理读取项目的锁定版本，例如 `.xcode-version`。在执行每个命令之前，它会运行 `tuist sandbox sync`。它会复制 Git 未忽略的文件（无论是否已提交），之后仅复制更改过的文件。Mac 已经安装了 [Tuist](#tuist-in-sandbox)（如果项目锁定了版本，则使用该版本），并已登录到你账户的缓存，代理会读取一次 Mac 的指南。然后，代理使用 `tuist sandbox exec` 运行诸如 `xcodebuild` 之类的命令，使用 `tuist sandbox cp` 将截图或构建的应用等结果复制回来，并在任务完成后删除 Mac。Mac 在最后一个命令结束后会继续运行 10 分钟，以便下一个命令立即启动；`tuist sandbox pause` 可以更早地释放它。被遗留的 Mac 会暂停，在两小时生命周期结束时归档，并在 14 天后删除；代理会在长时间构建前延长生命周期。

## Linux 和 macOS {#platforms}

**Linux** 沙盒运行 Ubuntu 24.04。每个 Linux 沙盒都有 16 个 vCPU，并可以突发使用其所在机器的空闲核心，因此其规格决定了内存大小：

- 2 GiB 内存 (`--vcpus 1 --memory-gb 2`)
- 4 GiB 内存 (`--vcpus 2 --memory-gb 4`，默认)
- 8 GiB 内存 (`--vcpus 4 --memory-gb 8`)
- 16 GiB 内存 (`--vcpus 8 --memory-gb 16`)
- 32 GiB 内存 (`--vcpus 16 --memory-gb 32`)
- 44 GiB 内存 (`--vcpus 16 --memory-gb 44`)

**macOS** 沙盒在搭载 Xcode 的 Apple silicon 上运行：

- 8 vCPU，8 GiB 内存（默认）
- 8 vCPU，16 GiB 内存
- 8 vCPU，24 GiB 内存

### 保证 CPU {#guaranteed-cpu}

Linux 沙盒保证每 GiB 内存获得四分之一 vCPU，例如 8 GiB 对应 2 vCPU，并可以使用机器上的更多空闲核心，最多可达 16 vCPU。这适合主要处于等待状态然后突发构建的代理。当构建即使在繁忙的机器上也需要更稳定的 CPU 时，请在创建沙盒时保证 1、2、4 或 8 个 vCPU；它将获得该值与内存保证中的较大者：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API 和 MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **保证是下限，而非上限。** 拥有 4 个保证 vCPU 的沙盒在核心空闲时仍可突发至 16 个。在资源竞争情况下，每个沙盒根据其保证比例获得 CPU。
- **按最低保证计费。** 运行中的沙盒按其使用的 CPU 计费，但绝不会低于其保证值。
- **沙盒在其生命周期内保持其保证。** 要更改保证，请创建新的沙盒。
- **macOS 沙盒始终拥有其完整规格**，因此不接受保证。

### 选择 Xcode {#xcode}

每个 macOS 沙盒运行一个 Xcode，你在创建时进行选择。它启动的镜像与用于该 Xcode 的 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 配置文件相同，因此代理使用与你的 CI 相同的工具链和模拟器。在 tuist.dev 上，macOS 沙盒目前提供：

- `26.6`（默认）
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

使用 `xcode_version`（CLI 中为 `--xcode`）选择一个，使用确切版本，就像 runner 配置文件那样：

| 位置 | 方式 |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API 和 MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Amp 的 Tuist Mac 插件 | 使用 `xcode` 的 `tuist_mac_start` |
| Amp orbs | orb 类型 `macos-xcode-26-1-1`（参见 <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>） |
| Claude Code 和 Claude Managed Agents | 在环境中设置 `xcode_version`，或在每个 Managed Agents 会话中设置（参见 <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>） |

- **如果不指定版本**，Mac 将使用默认版本。
- **如果请求 Tuist 未提供的版本，系统会拒绝**，并在错误信息中列出你可选择的版本，以便你了解当前可用的版本。
- **Tuist 不会读取你仓库中的 `.xcode-version`。** 由你或请求 Mac 的代理选择版本。MCP 工具和 Tuist Mac 插件会指示代理匹配项目锁定的版本。
- **沙盒在其生命周期内保持其 Xcode 版本不变。** 要使用其他 Xcode 构建，请创建新的沙盒。`xcodebuild -version` 显示 Mac 运行的 Xcode 版本。

## 安全性 {#security}

- 每个沙盒都是独立的虚拟机。沙盒之间以及沙盒与 CI 作业之间不共享文件系统、内存或进程。
- 沙盒归属于某个账户，该账户的任何成员都可以使用和管理它们。为集成（例如 Amp orb 或 Claude Code 会话）服务的沙盒保存该会话的工作内容和凭据：成员可以查看、暂停、恢复、归档和删除这些沙盒，但只有管理员才能在其中运行命令或向其上传文件。只有管理员才能连接集成。来自集成的会话只能访问该集成所连接账户的沙盒。
- 你提供给 Tuist 用于连接集成的凭据（例如 Amp 提供商令牌或 Claude 环境密钥）会以加密方式存储，且不再显示。
- 沙盒可以访问互联网。请以对待 CI 作业的方式对待代理从沙盒中能够访问的内容。
