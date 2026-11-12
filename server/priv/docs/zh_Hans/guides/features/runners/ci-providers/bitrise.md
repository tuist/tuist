---
{
  "title": "Bitrise",
  "titleTemplate": ":title · CI 提供商 · 运行器 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 运行器上运行 Bitrise 构建：连接你的工作区，将自托管运行器池与 Tuist 配置文件配对，并在工作流中选择该池。"
}
---
# Bitrise {#bitrise}

<!-- @snippet: ./_invite-only -->

> [!WARNING]
> **仅限私有仓库**
>
> Tuist 信任每个 Bitrise 构建：这些构建会共享你账户的缓存并可向其写入数据。不要将工作流用于构建来自公共仓库分叉的拉取请求的池进行配对。

Tuist 为你的 Bitrise 工作区提供自托管运行器池服务。选择其中一个池的构建将在与你配对的池所关联的 <.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link> 对应的 Tuist 机器上运行。你的工作流、触发器和日志仍保留在 Bitrise 上；只有运行机器发生变化。

1. **连接你的工作区。** 在 Bitrise 中，打开 **Workspace settings → Security → Workspace API tokens**，创建一个具有 **Viewer** 工作区角色和所有项目的 **Tester/QA** Bitrise CI 访问权限的令牌。在你的 Tuist 仪表板中，进入 **Settings → Integrations**，在 Bitrise 卡片上选择 **Connect**，然后粘贴该令牌。Tuist 会从令牌中读取工作区信息，加密存储该令牌，并且不再显示它。
2. **创建运行器池。** 在 Bitrise 中，打开 **Workspace settings → Infrastructure**，选择 **Add Runner pool**，并以其代表的机器命名，例如 `tuist-macos`。复制池令牌：Bitrise 仅显示一次。
3. **将池与 Tuist 配置文件配对。** 在 Tuist 的 Bitrise 卡片上，于 **Runner pools** 下选择池、其构建应运行的 Tuist 配置文件，粘贴池令牌，然后选择 **Add pool**。每个启用的账户初始都有两个配置文件：`tuist-linux` 和 `tuist-macos`。为你希望使用的每个配置文件添加一个池。
4. **在工作流中选择该池。** 在 Bitrise 的工作流编辑器中，打开 **Stacks & Machines** 并选择 **Self-Hosted Runner: tuist-macos**。在 `bitrise.yml` 中，设置池的栈，Tuist 会在池名称下方显示该栈：

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

5. **运行构建。** 几秒内，一台 Tuist 机器会连接到池，接管构建，并在完成后断开连接。该构建会出现在你 Tuist 仪表板的 **Runners** 部分，其中包含机器指标以及指向 Bitrise 的链接，日志仍保留在 Bitrise 上。

## 专用池 {#dedicated-pools}

仅将与你配对的池用于 Tuist。如果你自己的某台机器也连接到已配对的池，它会与 Tuist 竞争该池的构建任务。

## 运行器限制 {#runner-limit}

每台 Tuist 机器在运行构建时计为一个 Bitrise 运行器，并在断开连接后停止计数。因此，你的 Bitrise 计划的运行器限制会与 Tuist 并发限制一起，限制同时在你账户下通过 Tuist 运行的构建数量。

## 断开连接 {#disconnecting}

从 Bitrise 卡片中移除池会阻止 Tuist 接收该池的构建。已在运行的构建不受影响。

在 Bitrise 卡片上选择 **Disconnect** 会移除工作区及其所有池。
