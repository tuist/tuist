---
{
  "title": "Amp",
  "titleTemplate": ":title · 沙盒 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 沙盒上运行你的 Amp 工作区的 Orbs，支持 Linux 或 macOS。"
}
---
# Amp {#amp}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言，以申请账户访问权限。

[Amp](https://ampcode.com) 在 [orb](https://ampcode.com/docs/orbs)（已检出线程仓库的机器）中运行每个线程的工具。Tuist 可以作为你 Amp 工作区的[自托管 orb 提供商](https://ampcode.com/docs/orbs/self-hosted)：选择该提供商的每个线程都会在独立的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>（Linux 或 macOS）中运行。你无需自行运行或托管任何内容。

## 连接 Amp {#connect}

你需要同时是 Amp 工作区和 Tuist 账户的管理员。

1. 在 Amp 中，打开工作区的**Settings → Orbs**，点击**Add Orb Provider**，并为其命名，例如`tuist`。成员通过此名称选择提供商。复制`aop_live_…`令牌；Amp 仅显示一次。
2. 在 Amp 的提供商**Edit**对话框中，添加以下**Orb types**并选择默认值：

   | 类型 | 平台 | 规格 |
   | --- | --- | --- |
   | `linux` | Linux | 2 vCPU，4 GiB RAM，10 GB 工作区 |
   | `macos` | 带 Xcode 的 macOS | 8 vCPU，8 GiB RAM，10 GB 工作区 |

3. 在 Tuist 中，打开账户仪表板中的**Sandboxes**，点击 Amp 卡片上的**Connect**，并粘贴令牌。

一旦 Tuist 开始服务该提供商，卡片将显示**Connected**。一个 Tuist 账户对应一个提供商。任何能在 Amp 中使用该提供商的人，其运行的 orb 都将计入并收费到所连接的 Tuist 账户。要停止服务，请点击卡片上的**Disconnect**，或在 Amp 中关闭该提供商。

## 启动线程 {#start-a-thread}

在 Amp 的新线程创建器中，点击**Orb**，在**Self-Hosted**下选择 Tuist 提供商，然后选择`linux`或`macos`。通过 Amp CLI：

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

线程在其生命周期内保持其 orb 类型。如果没有指定类型，它将使用提供商的默认值。若要让每个新线程都使用同一平台，请在 Amp 的**Settings → Orbs**中的**Default Orb**下选择提供商及其类型。

Amp 会克隆仓库，运行你的`.agents/setup`脚本并设置 Git 凭据，这与它对每个 orb 的操作相同。每个 orb 还可以读取你账户的 Tuist <.localized_link href="/guides/features/cache">cache</.localized_link>。

## 暂停与保留 {#retention}

当线程空闲时，Amp 会暂停其 orb。下一条消息会恢复它，且文件保持完整。

- **Linux：** 运行中的进程在暂停后依然存活。长时间暂停的 orb 会移至归档存储，并在收到下一条消息时恢复，但不包含之前的进程。Linux orb 会保留其文件，直到 Amp 删除该线程的 orb。
- **macOS：** 处于暂停或错误状态达 7 天的 orb 会被删除。线程的下一条消息将启动一个新的 orb，并且 Amp 会再次运行`.agents/setup`。机器上的第一个 macOS orb 需要安装 Amp CLI，因此启动可能需要长达两分钟。

如果 orb 保持空闲而 Amp 未将其暂停（例如因为从未收到暂停指令），它将在十分钟后被暂停，此时几乎不占用 CPU。
