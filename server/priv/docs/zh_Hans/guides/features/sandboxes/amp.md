---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · 功能 · 指南 · Tuist",
  "description": "在 Tuist Sandboxes 上运行 Amp 工作区的 orbs，支持 Linux 或 macOS；或通过 Tuist Mac 插件为任意 Amp 线程提供 Mac 环境以执行 Xcode 构建。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前仅限受邀用户使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言，为你的账户申请访问权限。

[Amp](https://ampcode.com) 在一个 [orb](https://ampcode.com/docs/orbs)（即检出该线程仓库的机器）中运行每个线程的工具。Tuist 可以作为你 Amp 工作区的 [自托管 orb 提供商](https://ampcode.com/docs/orbs/self-hosted)：选择它的每个线程都会在独立的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> 中运行，支持 Linux 或 macOS。你无需自行运行或托管任何服务。

若希望线程继续使用当前的 orb，并仅在 Mac 上构建、测试和运行 Apple 平台代码，请改用 [Tuist Mac 插件](#remote-mac)。

## 连接 Amp {#connect}

你需要同时是 Amp 工作区和 Tuist 账户的管理员。

1. 在 Amp 中，打开工作区的 **Settings → Orbs**，点击 **Add Orb Provider**，并为其命名，例如 `tuist`。成员将按此名称选择提供商。复制 `aop_live_…` 令牌；Amp 仅显示一次。
2. 在 Amp 的提供商 **Edit** 对话框中，添加你想要提供的 **Orb types** 并选择默认值。Linux 类型与 [Amp 自有 orb](https://ampcode.com/docs/orbs/sizes-and-costs) 的规格匹配：

   | 类型 | 平台 | 规格 |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU，8 GiB RAM，10 GB 工作区 |
   | `linux-tiny` | Linux | 1 vCPU，2 GiB RAM，10 GB 工作区 |
   | `linux-small` | Linux | 2 vCPU，4 GiB RAM，10 GB 工作区 |
   | `linux-medium` | Linux | 4 vCPU，8 GiB RAM，10 GB 工作区（与 `linux` 相同） |
   | `linux-large` | Linux | 8 vCPU，16 GiB RAM，10 GB 工作区 |
   | `linux-xxlarge` | Linux | 16 vCPU，32 GiB RAM，10 GB 工作区 |
   | `linux-3xlarge` | Linux | 16 vCPU，44 GiB RAM，10 GB 工作区 |
   | `macos` | macOS（含 Xcode） | 8 vCPU，8 GiB RAM，10 GB 工作区 |

3. 在 Tuist 中，打开账户仪表板的 **Sandboxes**，点击 Amp 卡片上的 **Connect**，然后粘贴令牌。

当 Tuist 开始为该提供商提供服务时，卡片会显示 **Connected**。一个 Tuist 账户对应一个提供商。任何能在 Amp 中使用该提供商的人，其 orb 都将在已连接的 Tuist 账户上运行并计入该账户的费用。如需停止，请点击卡片上的 **Disconnect**，或在 Amp 中关闭该提供商。

## 启动线程 {#start-a-thread}

在 Amp 的新建线程界面中，点击 **Orb**，在 **Self-Hosted** 下选择 Tuist 提供商，然后选择一个类型，例如对于需求低于 `linux` 的仓库选择 `linux-small`，或对于需求更高的仓库选择 `linux-large`。通过 Amp CLI：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

线程在其生命周期内保持其 orb 类型不变。如果没有指定类型，它将使用提供商的默认值。若希望每个新线程都使用同一类型，请在 Amp 的 **Settings → Orbs** 中的 **Default Orb** 下选择提供商及其类型。

Amp 会克隆仓库，运行你的 `.agents/setup` 脚本并设置 Git 凭据，这与它对每个 orb 的操作一致。每个 orb 还可以读取你账户的 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暂停与保留 {#retention}

当线程空闲时，Amp 会暂停其 orb。下一条消息会恢复它，且文件保持完整。

- **Linux：** 运行中的进程在暂停后得以保留。长时间暂停的 orb 会移至归档存储，并在收到下一条消息时恢复，但不会恢复其进程。Linux orb 会保留其文件，直到 Amp 删除该线程的 orb。
- **macOS：** 暂停或处于错误状态达 7 天的 orb 会被删除。线程的下一条消息会启动一个新的 orb，并且 Amp 会再次运行 `.agents/setup`。机器上的第一个 macOS orb 会安装 Amp CLI，因此启动可能需要长达两分钟。

如果 orb 保持空闲而 Amp 未将其暂停（例如因为从未收到暂停指令），则在十分钟后几乎不占用 CPU 的情况下将其暂停。

## 从任何 Amp 线程使用 Mac {#remote-mac}

Tuist Mac 插件为 Amp 线程提供一个包含 Xcode、iOS 模拟器和 Homebrew 的 macOS 沙盒，而线程本身继续在其当前位置运行，例如在 Amp 自己的某个 Linux orb 上。向 Amp 下达任务，它会在需要时启动一台 Mac：

> 在设置界面添加深色模式切换开关，在 iOS 模拟器中运行应用，并给我看一张截图。

Amp 会在其运行位置继续编辑代码。在 Mac 上执行每条命令之前，插件会运行 `tuist sandbox sync`，它会复制 Git 未忽略的文件（无论是否已提交），之后仅复制发生更改的文件。Mac 生成的构建产物和其他被忽略的文件会保留在那里，因此构建可以保持增量进行。该插件添加了这些工具，以及一个 `remote-mac` 技能，用于告知 Amp 何时以及如何使用它们：

| 工具 | 功能 |
| --- | --- |
| `tuist_mac_start` | 创建或复用线程的 Mac，并进行同步 |
| `tuist_mac_shell` | 同步后，在 Mac 上运行一条命令 |
| `tuist_mac_screenshot` | 在线程中显示模拟器或屏幕 |
| `tuist_mac_download` | 将文件复制回来，例如已构建的 `.app` |
| `tuist_mac_stop` | 删除线程的 Mac |

Mac 本身没有 Tuist CLI：首次同步后，Amp 会在仓库根目录运行 `mise install`，以安装项目锁定的 Tuist 版本，而 `tuist_mac_shell` 会将 mise 的 shim 添加到 `PATH`。Mac 上的每条命令都会使用 Tuist 4.218.0 或更高版本独立<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">登录到你账户的缓存</.localized_link>；对于 4.215.0 至 4.217.x 版本，Amp 会先运行 `tuist auth login`。

一个线程使用一台 Mac。Tuist 会在其空闲时暂停它，下一条命令会恢复它。Amp 会在任务完成后删除它；遗留的 Mac 在暂停 14 天后会被删除。Mac 与其他沙盒一样，计入你的 Tuist 账户用量。

### 设置 {#remote-mac-setup}

1. **安装插件。** 它只是一个文件：[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。若要使 Amp 工作区中的所有成员都能使用它，工作区管理员需在线程中要求 Amp：

   > 将 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 添加到我们的工作区插件中。

   Amp 会将其提交到工作区的 [插件仓库](https://ampcode.com/docs/customize/global-plugins-and-skills)，并在推送前征求同意。若仅为自己安装，可改为要求“我的个人插件”，或将文件保存为仓库中的 `.amp/plugins/tuist-mac.ts` 以仅在该处使用。该插件是副本：如需更新，请要求 Amp 用同一 URL 的最新版本替换它。
2. **安装 Tuist CLI**到 Amp 运行的位置。在 orb 上，将其添加到仓库的 [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) 脚本中，例如 `mise use -g tuist@latest`，或 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **允许 CLI 使用你账户的沙盒。** 在 orb 上，按照 <.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link> 中的说明将你的 Amp 工作区连接到 Tuist 账户。随后 orb 会自动登录并获得沙盒访问权限。在其他地方，例如 Linux 机器上的 Amp CLI，请以账户成员身份运行 `tuist auth login`，或将 `TUIST_MAC_TOKEN` 设置为具有 `account:sandboxes:write` 范围的 <.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>，并加上 `ci` 以便 Mac 使用缓存。插件会将 `TUIST_MAC_TOKEN` 传递给 CLI 以替代 `TUIST_TOKEN`，因此当你的 orb 已有不包含该范围的 `TUIST_TOKEN` 时，也需设置它。
4. **指定要使用的账户**（如果仓库中没有包含 `project = "<account>/<project>"` 的 `tuist.toml`）。在 Linux 上，CLI 无法从 `Tuist.swift` 读取账户信息。请在 Amp 项目的环境变量中将 `TUIST_MAC_ACCOUNT` 设置为你的账户句柄。如果没有它，Amp 会将 `Tuist.swift` 的 `fullHandle` 传递给 `tuist_mac_start`。

CLI 仅通过 `tuist.dev` 访问 Mac，因此限制网络访问的环境只需允许该域名。若要使用不在 `PATH` 上的 CLI，请将 `TUIST_MAC_CLI` 设置为其路径。

不支持 Amp 插件的代理（如 Claude Code 或 Cursor）可以通过 Tuist MCP 服务器和 CLI 实现相同功能，详见 <.localized_link href="/guides/features/sandboxes#coding-agents">从编码代理在 Mac 上构建</.localized_link>。

### 使用 Tuist Mac 而非 Amp 的 macOS Satellites {#remote-mac-satellites}

Amp 还拥有自己的云 Mac——[macOS Satellites](https://ampcode.com/docs/orbs/mac)，目前面向加入等待列表的工作区提供测试版。当线程可以同时启动两者时，Amp 的内置指令会将 macOS 工作发送到其 satellites，因此很少选择该插件。若要让线程使用 Tuist Mac，请执行以下操作之一：

- **为自己关闭 macOS Satellites。** 每个成员可在 Amp 的 [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) 中的 **Mac Satellites** 下关闭它们。
- **为工作区关闭它们。** 当工作区的 orb [在 Tuist 上运行](#connect)时，工作区管理员可以在 Amp 工作区设置的 **Orbs** 下，将 **Where Orbs Run** 设置为 **Self-Hosted Only**。这样代理就无法启动 Amp 托管的 satellites，但成员也无法使用 Amp 的内置 orb，因此仅在所有线程都运行在你自己的 orb 提供商上时才这样做。
- **要求使用 Tuist Mac。** 在提示词中添加“对 macOS 工作使用 `tuist_mac_*` 工具，而非 macOS Satellites。”，或者将其添加到 Amp 工作区设置中的工作区代理指南中，以便每个线程都遵循该指引。
