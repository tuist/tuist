---
{
  "title": "Slack",
  "titleTemplate": ":title | 集成 | 指南 | Tuist",
  "description": "了解如何使用 Tuist 的 Slack 集成。"
}
---
# Tuist 的 Slack 集成 {#slack}

Tuist 的 Slack 集成将构建、测试和包体积洞察直接呈现在你的频道中。它将监控从团队需要刻意记住去做的事情，转变为自动发生的过程。例如，你的团队可以接收关于构建性能、缓存命中率或包体积趋势的每日摘要，并在关键指标出现退化或测试变得不稳定时立即收到警报。

本页面介绍了该集成的功能、如何按频道安装，以及 Tuist 如何处理你的数据。有关 Tuist 如何收集、管理和存储第三方数据的详细信息，请参阅我们的[隐私政策](https://tuist.dev/privacy)。

## 集成工作原理 {#how-it-works}

Tuist 通过 Slack 的[Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks)向 Slack 发送通知。该集成仅请求`incoming-webhook`作用域。每个通知目标（项目报告、警报规则、不稳定测试警报、自动化操作）都对应你在安装时选择的一个 Slack 频道。Slack 为每个频道创建一个 webhook URL，Tuist 会存储该 URL 以发送消息。

Tuist 绝不会读取你工作区中的消息、成员列表或任何其他数据。该集成仅向你明确授权的频道写入通知。

## 设置 {#setup}

### 项目报告 {#project-reports}

项目报告会将你的项目的构建、测试和缓存指标的每日摘要发送到你所选的 Slack 频道。

1. 在 Tuist 仪表板中打开你项目的通知设置。
2. 点击**Select Slack channel**，选择你希望 Tuist 发布消息的工作区和频道。Slack 会要求你授权`incoming-webhook`作用域并选择一个频道。
3. 选择你希望接收每日报告的星期几和时间。

![显示包含 Slack 报告配置的通知设置的图片](/images/guides/integrations/slack/notifications-settings.png)

配置完成后，Tuist 会向所选频道发送自动每日报告：

<img src="/images/guides/integrations/slack/report.png" alt="显示 Slack 报告消息的图片" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> 要向私有频道发布消息，请先在 Slack 中打开该频道，并在授权步骤中将其添加到集成可见的频道列表中。
> <!-- -->

### 警报规则 {#alert-rules}

当关键指标显著退化时，警报规则会在 Slack 中通知你，帮助你尽快发现构建变慢、缓存退化或测试减速的情况。

要创建警报规则，请进入你项目的通知设置并点击**Add alert rule**。你可以配置：

- **Name**：警报的描述性名称
- **Category**：要测量的内容（构建时长、测试时长、缓存命中率或包体积）
- **Metric**：如何聚合数据（p50、p90、p99 或平均值）
- **Deviation**：触发警报的百分比变化
- **Rolling window**：用于比较的最近运行次数
- **Branch**：对于缓存命中率警报，将比较限制在单个分支的运行上。留空则考虑所有分支。包体积警报始终针对单个分支。
- **Slack channel**：目标频道。你通过上述相同的`incoming-webhook`流程授权该频道。

例如，你可以创建一个警报，当 p90 构建时长相比前 100 次构建增加超过 20% 时触发。

当只有默认分支填充缓存时，将缓存命中率警报限定在该分支上是很有用的。触及底层模块的拉取请求分支确实会未命中缓存，如果将它们包括在内，会导致警报在预期的退化情况下触发。

缓存命中率警报只比较可以公平比较的时间窗口。两个窗口都必须包含与滚动窗口大小相同数量的运行，并且只出现在其中一个窗口中的缓存数据来源会被排除在两者之外。因此，尚未积累两倍于滚动窗口大小的运行次数的分支，或不匹配任何内容的分支名称，永远不会触发该规则。如果你将规则限定在低流量分支上，请保持滚动窗口足够小，以便该分支能够填满它。

当警报触发时，你将在 Slack 频道中收到如下消息：

<img src="/images/guides/integrations/slack/alert.png" alt="显示 Slack 警报消息的图片" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> 警报触发后，同一规则在 24 小时内不会再次触发。这可以防止在指标持续偏高时产生通知疲劳。
> <!-- -->

### 不稳定测试警报 {#flaky-test-alerts}

当 Tuist 检测到新的不稳定测试时，不稳定测试警报会立即触发，帮助你在测试不稳定性影响团队之前发现它。

要创建不稳定测试警报规则，请进入你项目的通知设置并点击**Add flaky test alert rule**。你可以配置：

- **Name**：警报的描述性名称
- **Trigger threshold**：过去 30 天内触发警报所需的不稳定运行的最小数量
- **Slack channel**：目标频道，通过`incoming-webhook`流程授权。

当测试变得不稳定并达到你的阈值时，你将收到一条包含直接链接的通知，以便调查该测试用例：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="显示 Slack 不稳定测试警报消息的图片" style="max-width: 500px;" />

### 慢速测试警报 {#slow-test-alerts}

当单个测试用例的运行速度慢于你设定的时长时，慢速测试警报会通知你，这样你就无需在“测试用例”表中检查慢速测试。

要创建一个慢速测试警报，请进入你项目的**Settings → Automations**，点击**Add automation**，并在**When**下选择**Test duration**。你可以配置：

- **Statistic**：测试用例运行时长的平均值、p50、p90 或 p99。
- **Comparison**和**Seconds**：例如，大于或等于 10 秒。
- **Window**：计算统计数据的日历窗口，例如`30d`。
- **Actions**：默认添加一个**Send Slack notification**操作。你也可以将测试静音或跳过。

时长的计算方式与“测试用例”表中的相同，涵盖每个分支上的 CI 和本地运行。测试用例在窗口内至少需要五次运行才会被测量。每个测试用例在超过阈值时触发一次；启用**Recovery**后，一旦测试在恢复窗口期内回到阈值以下，自动化将重新激活（并执行其恢复操作）。

## 断开集成 {#disconnect}

要停止通知，请在 Tuist 仪表板中从报告、警报规则或自动化操作中移除已配置的 Slack 频道。要完全撤销 Tuist 的访问权限，请通过 Slack 内部的**Settings & administration → Manage apps**移除 webhook 集成。
