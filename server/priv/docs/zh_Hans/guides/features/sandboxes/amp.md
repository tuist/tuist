---
{
  "title": "Amp",
  "titleTemplate": ":title · 沙盒 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 沙盒（Linux 或 macOS）上运行你的 Amp 工作区 orbs，或通过 Tuist Mac 插件为任意 Amp 线程提供 Mac 环境以执行 Xcode 构建。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前仅限受邀用户使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中联系我们，为你的账户申请访问权限。

[Amp](https://ampcode.com)在[orb](https://ampcode.com/docs/orbs)（已检出线程仓库的机器）中运行每个线程的工具。Tuist 可以作为你 Amp 工作区的[自托管 orb 提供商](https://ampcode.com/docs/orbs/self-hosted)：选择它的每个线程都会在 Linux 或 macOS 上的独立 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>中运行。你无需自行运行或托管任何内容。

若要让线程保持在当前的 orb 上，并仅在 Mac 上构建、测试和运行 Apple 平台代码，请改用[Tuist Mac 插件](#remote-mac)。

## 连接 Amp {#connect}

你需要同时是 Amp 工作区和 Tuist 账户的管理员。

1. 在 Amp 中，打开工作区的**Settings → Orbs**，点击**Add Orb Provider**，并为其命名，例如`tuist`。成员通过此名称选择提供商。复制`aop_live_…`令牌；Amp 仅显示一次。
2. 在 Amp 中提供商的**Edit**对话框中，添加你想要提供的**Orb types**并选择默认值。Linux 类型与[Amp 自己的 orb](https://ampcode.com/docs/orbs/sizes-and-costs)的内存配置相匹配。每种类型保证每 GiB 内存分配四分之一 vCPU，并在机器有空闲核心时突发至 16 vCPU（参见<.localized_link href="/guides/features/sandboxes#guaranteed-cpu">Guaranteed CPU</.localized_link>）：

   | 类型 | 规格 |
   | --- | --- |
   | `linux` | Linux，8 GiB RAM，2 个保证 vCPU |
   | `linux-tiny` | Linux，2 GiB RAM，0.5 个保证 vCPU |
   | `linux-small` | Linux，4 GiB RAM，1 个保证 vCPU |
   | `linux-medium` | 与`linux`相同 |
   | `linux-large` | Linux，16 GiB RAM，4 个保证 vCPU |
   | `linux-xxlarge` | Linux，32 GiB RAM，8 个保证 vCPU |
   | `linux-3xlarge` | Linux，44 GiB RAM，11 个保证 vCPU |
   | `macos` | macOS，默认 Xcode，8 vCPU，8 GiB RAM |
   | `macos-xcode-<version>` | macOS，使用该[Xcode](#xcode)，8 vCPU，8 GiB RAM |

   Linux 类型的工作区为 10 GB，macOS 类型为 30 GB。

3. 在 Tuist 中，打开账户仪表板中的**Sandboxes**，点击 Amp 卡片上的**Connect**，并粘贴令牌。

一旦 Tuist 开始为该提供商提供服务，卡片将显示**Connected**。一个 Tuist 账户服务于一个提供商。任何能在 Amp 中使用该提供商的人，其 orb 都将在连接的 Tuist 账户上运行并由该账户计费。要停止服务，请点击卡片上的**Disconnect**，或在 Amp 中关闭该提供商。

## 启动线程 {#start-a-thread}

在 Amp 的新线程编辑器中，点击**Orb**，在**Self-Hosted**下选择 Tuist 提供商，并选择一种类型，例如对于需求低于`linux`的仓库选择`linux-small`，对于需求更高的则选择`linux-large`。从 Amp CLI 执行：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

线程在其生命周期内保持其 orb 类型不变。如果没有指定类型，它将使用提供商的默认类型。若要对每个新线程使用同一种类型，请在 Amp 的**Settings → Orbs**中的**Default Orb**下选择提供商及其类型。

### 选择 Xcode {#xcode}

`macos`运行默认的<.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>。如需其他版本，请添加以其命名的 orb 类型，并将点号替换为短横线：`macos-xcode-26-1-1`运行 Xcode 26.1.1，`macos-xcode-27-0`运行 Xcode 27.0。为你的仓库锁定的每个 Xcode 添加一个类型，并像其他类型一样按线程选择：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

如果 Tuist 不提供某个 Xcode 对应的类型，当新 orb 启动时会失败。如果 orb 已经在该 Xcode 上启动，即使 Tuist 停止提供该 Xcode，它仍会继续恢复运行。

Amp 会克隆仓库，运行你的`.agents/setup`脚本并设置 Git 凭据，这与它对每个 orb 的操作相同。每个 orb 还可以读取你账户的 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暂停与保留 {#retention}

当线程空闲时，Amp 会暂停其 orb。下一条消息会恢复它，且文件保持完整。

- **Linux：** 运行中的进程在暂停后依然存在。长时间暂停的 orb 会移至归档存储，并在收到下一条消息时恢复，但不保留其进程。Linux orb 会保留其文件，直到 Amp 删除该线程的 orb。
- **macOS：** 暂停或处于错误状态达 7 天的 orb 会被删除。线程的下一条消息会启动一个新的 orb，并且 Amp 会再次运行`.agents/setup`。机器上的第一个 macOS orb 需要安装 Amp CLI，因此启动可能需要长达两分钟。

如果 orb 保持空闲而 Amp 未将其暂停（例如因为从未收到暂停指令），它将在十分钟后暂停，此时几乎不占用 CPU。

## 从任何 Amp 线程使用 Mac {#remote-mac}

Tuist Mac 插件为 Amp 线程提供一个带有 Xcode、iOS 模拟器和 Homebrew 的 macOS sandbox，而线程继续在其当前位置运行，例如在 Amp 自己的 Linux orb 之一上。向 Amp 请求工作，它会在需要时启动一台 Mac：

> 在设置屏幕中添加深色模式切换开关，在 iOS 模拟器中运行应用，并给我看一张截图。

Amp 在其运行位置继续编辑代码。在 Mac 上执行每条命令之前，插件会运行`tuist sandbox sync`，它会复制 Git 未忽略的文件（无论是否已提交），之后仅复制发生变化的文件。Mac 创建的构建产物和其他被忽略的文件会保留在那里，因此构建保持增量状态。插件添加了这些工具，以及一个`remote-mac`技能，用于告知 Amp 何时以及如何使用它们：

| 工具 | 作用 |
| --- | --- |
| `tuist_mac_start` | 创建线程的 Mac，或复用现有实例并同步 |
| `tuist_mac_shell` | 同步后在 Mac 上运行命令 |
| `tuist_mac_screenshot` | 在线程中显示模拟器或屏幕 |
| `tuist_mac_download` | 将文件复制回来，例如构建好的`.app` |
| `tuist_mac_stop` | 删除线程的 Mac |

Mac 上装有 Tuist CLI，并在项目通过 mise 锁定版本时运行该版本；`tuist_mac_shell`会将 mise 的 shim 置于`PATH`最前面。Mac 上的每条命令都会使用 Tuist 4.218.0 或更高版本单独<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">登录到你账户的缓存</.localized_link>；对于 4.215.0 到 4.217.x 版本，Amp 会先运行`tuist auth login`。

一个线程使用一台 Mac。Amp 会将仓库锁定的<.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>传递给`tuist_mac_start`（例如在`.xcode-version`中指定），或者你可以指定一个（“使用 Xcode 26.1.1”）；如果不指定，Mac 将运行默认版本。Mac 会保留其 Xcode，因此切换意味着停止当前实例并启动另一个。Tuist 会在空闲时暂停它，下一条命令会恢复它。任务完成后 Amp 会将其删除；遗留的 Mac 在暂停 14 天后会被删除。Mac 与其他 sandbox 一样计入你的 Tuist 账户用量。

### 设置{#remote-mac-setup}

1. **安装插件。** 它只有一个文件：[`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts)。要让 Amp 工作区中的所有成员都能使用它，工作区管理员需在线程中向 Amp 发出请求：

   > 将 https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts 添加到我们的工作区插件中。

   Amp 会将其提交到工作区的[插件仓库](https://ampcode.com/docs/customize/global-plugins-and-skills)，并在推送前征求确认。如果只想为自己安装，可以请求“我的个人插件”，或者将文件保存为仓库中的`.amp/plugins/tuist-mac.ts`以便仅在该仓库中使用。该插件是副本：要更新它，请让 Amp 用同一 URL 的最新版本替换它。
2. **安装 Tuist CLI**到 Amp 运行的位置。在 orb 上，将其添加到仓库的[`.agents/setup`](https://ampcode.com/docs/orbs/customizing)脚本中，例如`mise use -g tuist@latest`，或`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. **允许 CLI 使用你账户的 sandbox。** 在 orb 上，按照<.localized_link href="/guides/server/authentication#amp-orbs">Amp orbs</.localized_link>中的说明将你的 Amp 工作区连接到 Tuist 账户。orb 随后会自动登录并获得 sandbox 访问权限。在其他地方（例如 Linux 机器上的 Amp CLI），以账户成员身份运行`tuist auth login`，或将`TUIST_MAC_TOKEN`设置为具有`account:sandboxes:write`范围的<.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>，并为 Mac 添加`ci`以使用缓存。插件会将`TUIST_MAC_TOKEN`传递给 CLI 以替代`TUIST_TOKEN`，因此即使你的 orb 已有不带该范围的`TUIST_TOKEN`，也需要设置它。
4. **指定要使用的账户**（如果仓库中没有包含`project = "<account>/<project>"`的`tuist.toml`）。在 Linux 上，CLI 无法从`Tuist.swift`读取账户信息。请在 Amp 项目的环境变量中将`TUIST_MAC_ACCOUNT`设置为你的账户句柄。如果没有设置，Amp 会将`Tuist.swift`的`fullHandle`传递给`tuist_mac_start`。

CLI 仅通过`tuist.dev`访问 Mac，因此限制网络访问的环境需要仅允许该域名。要使用不在`PATH`上的 CLI，请将`TUIST_MAC_CLI`设置为其路径。

不支持 Amp 插件的代理（例如 Claude Code 或 Cursor）可以通过 Tuist MCP 服务器和 CLI 实现相同功能，如<.localized_link href="/guides/features/sandboxes#coding-agents">从编码代理在 Mac 上构建</.localized_link>中所述。

### 使用 Tuist Mac 而非 Amp 的 macOS Satellites {#remote-mac-satellites}

Amp 还拥有自己的云 Mac——[macOS Satellites](https://ampcode.com/docs/orbs/mac)，面向加入等待列表的工作区提供测试版。当线程可以同时启动两者时，Amp 的内置指令会将 macOS 工作负载发送到其 satellites，因此很少选择该插件。要让线程使用 Tuist Mac，请执行以下操作之一：

- **为自己关闭 macOS Satellites。** 每个成员可以在 Amp 的[Settings → Experimental Features](https://ampcode.com/settings/experimental-features)下的**Mac Satellites**中关闭它们。
- **为工作区关闭它们。** 当工作区的 orb [run on Tuist](#connect)时，工作区管理员可以在 Amp 工作区设置的**Orbs**下，将**Where Orbs Run**设置为**Self-Hosted Only**。这样代理就无法启动 Amp 托管的 satellites，但成员也无法使用 Amp 内置的 orb，因此仅在所有线程都运行在你自己的 orb 提供商上时才这样做。
- **请求使用 Tuist Mac。** 在提示词中添加“对 macOS 工作使用`tuist_mac_*`工具，而非 macOS Satellites。”，或者将其添加到 Amp 工作区设置中的工作区代理指南，以便每个线程都遵循该指引。
