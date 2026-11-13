---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "在 Tuist Sandboxes 上运行你的 Amp 工作区 orbs，支持 Linux 或 macOS；或者通过 Tuist Mac 插件为任意 Amp 线程提供 Mac 环境以执行 Xcode 构建。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前仅限受邀用户。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中与我们取得联系，以申请你的账户访问权限。

[Amp](https://ampcode.com)在[orb](https://ampcode.com/docs/orbs)（已检出线程仓库的机器）中运行每个线程的工具。Tuist 可以作为你 Amp 工作区的[自托管 orb 提供商](https://ampcode.com/docs/orbs/self-hosted)：选择该提供商的每个线程都会在独立的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>中运行，支持 Linux 或 macOS。你无需自行运行或托管任何服务。

若希望线程保留在当前 orb 上，并仅在 Mac 上构建、测试和运行 Apple 平台代码，请改用[Tuist Mac 插件](#remote-mac)。

## 连接 Amp {#connect}

你需要同时是 Amp 工作区和 Tuist 账户的管理员。

1. 在 Amp 中，打开工作区的**Settings → Orbs**，点击**Add Orb Provider**，并为其命名，例如`tuist`。成员将通过此名称选择提供商。复制`aop_live_…`令牌；Amp 仅显示一次。
2. 在 Amp 的提供商**Edit**对话框中，添加你想要提供的**Orb types**并选择默认值。Linux 类型与[Amp 自有 orb](https://ampcode.com/docs/orbs/sizes-and-costs)的规格相匹配：

   | 类型 | 平台 | 规格 |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU，8 GiB RAM，10 GB 工作区 |
   | `linux-tiny` | Linux | 1 vCPU，2 GiB RAM，10 GB 工作区 |
   | `linux-small` | Linux | 2 vCPU，4 GiB RAM，10 GB 工作区 |
   | `linux-medium` | Linux | 4 vCPU，8 GiB RAM，10 GB 工作区（与`linux`相同） |
   | `linux-large` | Linux | 8 vCPU，16 GiB RAM，10 GB 工作区 |
   | `linux-xxlarge` | Linux | 16 vCPU，32 GiB RAM，10 GB 工作区 |
   | `linux-3xlarge` | Linux | 16 vCPU，44 GiB RAM，10 GB 工作区 |
   | `macos` | 带 Xcode 的 macOS | 8 vCPU，8 GiB RAM，10 GB 工作区 |

3. 在 Tuist 中，打开账户仪表板中的**Sandboxes**，点击 Amp 卡片上的**Connect**，并粘贴令牌。

一旦 Tuist 开始为该提供商提供服务，卡片将显示**Connected**。一个 Tuist 账户对应一个提供商。任何能在 Amp 中使用该提供商的人，其运行的 orb 都将计入并关联到已连接的 Tuist 账户。若要停止，请点击卡片上的**Disconnect**，或在 Amp 中关闭该提供商。

## 启动线程 {#start-a-thread}

在 Amp 的新建线程界面中，点击**Orb**，在**Self-Hosted**下选择 Tuist 提供商，并挑选一种类型，例如对于需求低于`linux`的仓库选择`linux-small`，对于需求更高的则选择`linux-large`。通过 Amp CLI：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

线程在其生命周期内保持其 orb 类型不变。若未指定类型，则使用提供商的默认值。若希望所有新线程都使用同一种类型，请在 Amp 的**Settings → Orbs**中的**Default Orb**下选择提供商及其类型。

Amp 会克隆仓库，运行你的`.agents/setup`脚本并设置 Git 凭据，这与它对每个 orb 的操作一致。每个 orb 还可以读取你账户的 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暂停与保留 {#retention}

当线程空闲时，Amp 会暂停其 orb。下一条消息会恢复它，且文件保持完整。

- **Linux：** 运行中的进程在暂停后依然存在。长时间暂停的 orb 会移至归档存储，并在收到下一条消息时恢复，但不保留其进程。Linux orb 会保留其文件，直到 Amp 删除该线程的 orb。
- **macOS：** 处于暂停状态或错误状态达 7 天的 orb 会被删除。线程的下一条消息会启动一个新的 orb，并且 Amp 会再次运行`.agents/setup`。机器上的第一个 macOS orb 需要安装 Amp CLI，因此启动可能需要长达两分钟。

若 orb 保持空闲而 Amp 未将其暂停（例如因为从未收到暂停指令），则在十分钟后几乎不占用 CPU 的情况下将其暂停。

## 从任何 Amp 线程使用 Mac {#remote-mac}

Tuist Mac 插件为 Amp 线程提供一个带 Xcode、iOS 模拟器和 Homebrew 的 macOS 沙盒，而线程继续在其当前位置运行，例如在 Amp 自己的某个 Linux orb 上。让 Amp 执行任务，它会在需要时启动一台 Mac：

> 在设置界面添加深色模式切换开关，在 iOS 模拟器中运行应用，并给我看一张截图。

Amp 会在其运行位置继续编辑代码。在 Mac 上执行每条命令之前，插件会运行`tuist sandbox sync`，它会复制 Git 未忽略的文件（无论是否已提交），之后仅复制发生变化的文件。Mac 创建的构建产物和其他被忽略的文件会保留在那里，因此构建保持增量状态。该插件添加了这些工具，以及一个`remote-mac`技能，用于告知 Amp 何时以及如何使用它们：

| 工具 | 功能 |
| --- | --- |
| `tuist_mac_start` | 创建或复用线程的 Mac，并同步文件 |
| `tuist_mac_shell` | 同步文件，然后在 Mac 上运行命令 |
| `tuist_mac_screenshot` | 在线程中显示模拟器或屏幕 |
| `tuist_mac_download` | 将文件复制回来，例如构建好的`.app` |
| `tuist_mac_stop` | 删除线程的 Mac |

一个线程使用一台 Mac。当它空闲时，Tuist 会将其暂停，下一条命令会恢复它。任务完成后，Amp 会将其删除；若 Mac 被遗留，则在暂停 14 天后删除。Mac 与其他沙盒一样计入你的 Tuist 账户。

### 设置 {#remote-mac-setup}

1. **安装插件。** 它只有一个文件：[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。若要使其对 Amp 工作区中的所有成员可用，工作区管理员需在线程中向 Amp 发出请求：

   > 将 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 添加到我们的工作区插件中。

   Amp 会将其提交到工作区的[plugin repository](https://ampcode.com/docs/customize/global-plugins-and-skills)，并在推送前征求同意。若只想为自己安装，请改为请求“my personal plugins”；或者将该文件保存为仓库中的`.amp/plugins/tuist-mac.ts`，以便仅在该仓库中使用。该插件是一个副本：要更新它，请让 Amp 用同一 URL 的最新版本替换它。
2. **安装 Tuist CLI**到 Amp 运行的位置。在 orb 上，将其添加到仓库的[`.agents/setup`](https://ampcode.com/docs/orbs/customizing)脚本中，例如`mise use -g tuist@latest`，或`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **允许 CLI 使用你账户的沙盒。** 在 orb 上，按照<.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link>中的说明将你的 Amp 工作区连接到 Tuist 账户。随后 orb 会自动登录并获得沙盒访问权限。在其他地方（例如 Linux 机器上的 Amp CLI），以账户成员身份运行`tuist auth login`，或将`TUIST_MAC_TOKEN`设置为具有`account:sandboxes:write`范围的<.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>。插件会将`TUIST_MAC_TOKEN`传递给 CLI 以替代`TUIST_TOKEN`，因此即使你的 orb 已有不包含该范围的`TUIST_TOKEN`，也需设置它。
4. **指定要使用的账户**（如果仓库中没有包含`project = "<account>/<project>"`的`tuist.toml`）。在 Linux 上，CLI 无法从`Tuist.swift`读取账户信息。请在 Amp 项目的环境变量中将`TUIST_MAC_ACCOUNT`设置为你的账户句柄。若未设置，Amp 会将`Tuist.swift`的`fullHandle`传递给`tuist_mac_start`。

CLI 仅通过`tuist.dev`访问 Mac，因此限制网络访问的环境只需允许该域名。若要使用不在`PATH`上的 CLI，请将`TUIST_MAC_CLI`设置为其路径。

不支持 Amp 插件的代理（如 Claude Code 或 Cursor）可以通过 Tuist MCP 服务器和 CLI 实现相同功能，详见<.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>。

### 使用 Tuist Mac 而非 Amp 的 macOS Satellites {#remote-mac-satellites}

Amp 还拥有自己的云 Mac——[macOS Satellites](https://ampcode.com/docs/orbs/mac)，面向加入等待列表的工作区提供测试版。当线程可以同时启动两者时，Amp 的内置指令会将 macOS 任务发送给其 satellites，因此很少选择该插件。若要让线程使用 Tuist Mac，请执行以下操作之一：

- **为自己关闭 macOS Satellites。** 每个成员可在 Amp 的[Settings → Experimental Features](https://ampcode.com/settings/experimental-features)中的**Mac Satellites**下关闭它们。
- **为工作区关闭它们。** 当工作区的 orb [run on Tuist](#connect)时，工作区管理员可以在 Amp 工作区设置的**Orbs**下，将**Where Orbs Run**设置为**Self-Hosted Only**。此时代理无法启动 Amp 托管的 satellites，但成员也无法使用 Amp 内置的 orb，因此仅在所有线程都运行在你自己的 orb 提供商上时才执行此操作。
- **要求使用 Tuist Mac。** 在提示词中添加“Use the `tuist_mac_*` tools for macOS work, not macOS Satellites.”，或者将其添加到 Amp 工作区设置中的工作区代理指南中，以便每个线程都遵循该指引。
