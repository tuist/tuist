---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI 提供商 · Runner · 功能 · 指南 · Tuist",
  "description": "在 Tuist Runner 上运行你的首个 Buildkite 任务：连接集群，以 Tuist 配置文件命名队列，并在步骤中指定该队列。"
}
---
# Buildkite {#buildkite}

<!-- @snippet: ./_invite-only -->

Tuist 会监控你 Buildkite 集群中的自托管队列，并在运行器集群上执行找到的任务。你的流水线继续在 Buildkite 上运行；只有计算资源发生变化。要在运行器集群上执行任务，需要进行三项更改：连接你的集群、以 Tuist <.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link> 命名队列，并在步骤中指向该队列。

1. **连接你的集群。** 在 Buildkite 中，打开你的集群，进入 **Agent Tokens**，创建一个令牌；它以 `bkct_` 开头。在你的 Tuist 仪表板中，进入 **Settings → Integrations**，在 Buildkite 卡片上选择 **Connect**，然后输入你的组织标识符和令牌。令牌以加密方式存储，之后不再显示。如需稍后更改组织或轮换令牌，请编辑卡片上的字段并选择 **Save changes**。Tuist 将在一分钟内开始监控该集群。
2. **以 Tuist 配置文件命名队列。** 每个已启用的账户都预置了两个可直接使用的 <.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>：`linux` 和 `macos`。当任务的队列键与配置文件的标签匹配时，任务会被接收。在你的集群中创建键为 `tuist-linux` 和 `tuist-macos` 的自托管队列，然后在步骤中指向其中一个：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

3. **推送并观察。** 任务进入队列后由运行器领取，并流式传输回 Tuist 仪表板的 **Runners** 部分，你可以在此查看其日志、步骤和机器指标。运行器使用仅对该任务有效的凭据从任务内部发送日志，因此不需要 Buildkite API 令牌。

## 暂停与断开连接 {#pausing-and-disconnecting}

暂停 Buildkite 队列的分发会阻止 Tuist 从中领取新任务。已在运行的任务不受影响。

在 **Settings → Integrations** 下的 Buildkite 卡片中断开集群连接，将完全停止 Tuist 对其的监控。

## 缓存卷 {#cache-volumes}

使用 <.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link> 在任务之间保留 Xcode、模块和 Gradle 缓存以及其他目录。在检出代码之后、在使用它们的命令之前添加这些卷。
