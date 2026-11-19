---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI 提供商 · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist Runners 上运行你的首个 Buildkite 作业：连接集群，以 Tuist 配置文件命名队列，并从步骤中指向该队列。"
}
---
# Buildkite {#buildkite}

<!-- @snippet: ./_invite-only -->

Tuist 会监控你 Buildkite 集群中的自托管队列，并在其计算资源池中运行找到的作业。你的流水线继续在 Buildkite 上运行；仅计算资源发生变化。要在计算资源池上运行作业，需要进行三项更改：连接你的集群、以 Tuist <.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link> 命名队列，并在步骤中指定该队列。

1. **连接你的集群。** 在 Buildkite 中，打开你的集群，进入**Agent Tokens**并创建一个令牌；它以`bkct_`开头。在 Tuist 仪表板中，进入**Settings → Integrations**，在 Buildkite 卡片上选择**Connect**，然后输入你的组织 slug 和令牌。令牌以加密方式存储，之后不再显示。如需稍后更改组织或轮换令牌，请编辑卡片上的字段并选择**Save changes**。Tuist 将在一分钟内开始监控该集群。
2. **以 Tuist 配置文件命名队列。** 每个已启用的账户都自带两个可直接使用的<.localized_link href="/guides/features/runners/profiles">配置文件</.localized_link>：`linux`和`macos`。当作业的队列键与配置文件的标签匹配时，该作业就会被接收。在你的集群中创建键为`tuist-linux`和`tuist-macos`的自托管队列，然后在步骤中指定其中一个：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

3. **推送并观察。** 作业会被加入队列，由 runner 领取，并流式传输回 Tuist 仪表板的**Runners**部分，你可以在那里查看其日志、步骤和机器指标。runner 会使用仅针对该作业的作用域凭据从作业内部发送日志，因此不需要 Buildkite API 令牌。

## 暂停和断开连接 {#pausing-and-disconnecting}

暂停 Buildkite 队列的分发会阻止 Tuist 从中获取新作业。已在运行的作业不受影响。

在**Settings → Integrations**下的 Buildkite 卡片上断开集群连接会使 Tuist 完全停止监控该集群。

## 缓存卷 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link>在作业之间保留 Xcode、模块和 Gradle 缓存以及其他目录。在检出代码之后、在使用它们的命令之前添加这些卷。
