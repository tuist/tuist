---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI 提供商 · 运行器 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 运行器上运行你的 Bitrise 构建：连接工作区，将自托管运行器池与 Tuist 配置文件配对，并在工作流中选择该池。"
}
---
# Bitrise {#bitrise}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Runners 目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言，为你的账户申请访问权限。

> [!WARNING]
> **仅限私有仓库**
>
> Tuist 信任每一个 Bitrise 构建：构建会共享你账户的缓存并可以写入其中。不要将工作流会从公共仓库的 fork 构建拉取请求的池进行配对。

Tuist 为你的 Bitrise 工作区提供自托管运行器池。选择其中一个池的构建会在与你配对的池所关联的<.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>对应的 Tuist 机器上运行。你的工作流、触发器和日志仍保留在 Bitrise 上；只有运行机器发生变化。

1. **申请访问权限。** 在测试期间，Runners 仅限邀请使用。[联系我们](mailto:contact@tuist.dev)并提供你希望启用的账户。
2. **连接你的工作区。** 在 Bitrise 中，打开**Workspace settings → Security → Workspace API tokens**，创建一个具有**Viewer**工作区角色和对所有项目的 Bitrise CI 具有**Tester/QA**访问权限的令牌。在你的 Tuist 仪表板中，前往**Settings → Integrations**，在 Bitrise 卡片上选择**Connect**，然后粘贴令牌。Tuist 会从令牌中读取工作区信息，加密存储令牌，并且不再显示它。
3. **创建运行器池。** 在 Bitrise 中，打开**Workspace settings → Infrastructure**，选择**Add Runner pool**，并以它所代表的机器命名，例如`tuist-macos`。复制池令牌：Bitrise 仅显示一次。
4. **将池与 Tuist 配置文件配对。** 在 Tuist 的 Bitrise 卡片上，在**Runner pools**下，选择池、其构建应运行的 Tuist 配置文件，粘贴池令牌，然后选择**Add pool**。每个启用的账户初始都有两个配置文件：`tuist-linux`和`tuist-macos`。为你希望使用的每个配置文件添加一个池。
5. **在工作流中选择池。** 在 Bitrise 的 Workflow Editor 中，打开**Stacks & Machines**并选择**Self-Hosted Runner: tuist-macos**。在`bitrise.yml`中，设置池的栈，Tuist 会在池名称下方显示该栈：

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

6. **运行构建。** 几秒钟内，一台 Tuist 机器会连接到池，接收构建，并在完成后断开连接。该构建会出现在你的 Tuist 仪表板的**Runners**部分，包含其机器指标以及指向 Bitrise 的链接，日志仍保留在那里。

## 专用池{#dedicated-pools}

仅将与你配对的池用于 Tuist。如果你自己的某台机器也连接到已配对的池，它会与 Tuist 竞争该池的构建任务。

## 运行器限制{#runner-limit}

每台 Tuist 机器在运行构建时计为一个 Bitrise 运行器，并在断开连接后停止计数。因此，你的 Bitrise 计划的运行器限制会与你的 Tuist 并发限制一起，限制同时有多少构建在 Tuist 上运行。

## 断开连接{#disconnecting}

从 Bitrise 卡片中移除池会阻止 Tuist 接收该池的构建。已在运行的构建不受影响。

在 Bitrise 卡片上选择**Disconnect**会移除工作区及其所有池。
