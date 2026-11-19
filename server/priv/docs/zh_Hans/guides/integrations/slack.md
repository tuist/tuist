---
{
  "title": "Slack",
  "titleTemplate": ":title | 集成 | 指南 | Tuist",
  "description": "了解如何使用 Tuist 的 Slack 集成。"
}
---
# Tuist 与 Slack 的集成 {#slack}

Tuist 与 Slack 的集成将构建、测试和包体积洞察直接呈现在你的频道中。它将监控从团队需要刻意记住去做的事情，转变为自动发生的过程。例如，你的团队可以接收关于构建性能、缓存命中率或包体积趋势的每日摘要，并在关键指标出现回归或测试变得不稳定时立即收到警报。

本页介绍了该集成的功能、如何按频道安装，以及 Tuist 如何处理你的数据。有关 Tuist 如何收集、管理和存储第三方数据的详细信息，请参阅我们的[隐私政策](https://tuist.dev/privacy)。

## 集成工作原理 {#how-it-works}

Tuist 通过 Slack 的[Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks)向 Slack 发送通知。该集成仅请求`incoming-webhook`权限范围。每个通知目标（项目报告、警报规则、不稳定测试警报、自动化操作）都对应你在安装时选择的一个 Slack 频道。Slack 为每个频道创建一个 webhook URL，Tuist 存储该 URL 以发送消息。

Tuist 绝不会读取你工作区中的消息、成员列表或任何其他数据。该集成仅向你明确授权的频道写入通知。

## 设置 {#setup}

### 项目报告 {#project-reports}

项目报告会将你的项目的构建、测试和缓存指标的每日摘要发送到你所选的 Slack 频道。

1. 在 Tuist 仪表板中打开你项目的通知设置。
2. 点击**选择 Slack 频道**，并选择你希望 Tuist 发布到的工作区和频道。Slack 会要求你授权`incoming-webhook`权限范围并选择一个频道。
3. 选择你希望接收每日报告的星期几和时间。

![显示包含 Slack 报告配置的通知设置的图片](/images/guides/integrations/slack/notifications-settings.png)

配置完成后，Tuist 会向所选频道发送自动每日报告：

<img src="/images/guides/integrations/slack/report.png" alt="显示 Slack 报告消息的图片" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> 要向私有频道发布消息，请先在 Slack 中打开该频道，并在授权步骤中将其添加到对集成可见的频道列表中。
> <!-- -->

### 警报规则 {#alert-rules}

当关键指标出现显著回归时，警报规则会在 Slack 中通知你，帮助你尽快发现构建变慢、缓存退化或测试减速的情况。

要创建警报规则，请前往你项目的通知设置并点击**添加警报规则**。你可以配置：

- **名称**：警报的描述性名称
- **类别**：要测量的内容（构建时长、测试时长、缓存命中率或包体积）
- **指标**：如何聚合数据（p50、p90、p99 或平均值）
- **偏差**：触发警报的百分比变化
- **滚动窗口**：用于比较的最近运行次数
- **分支**：对于缓存命中率警报，将比较限制在单个分支上的运行。留空则考虑所有分支。包体积警报始终针对单个分支。
- **Slack 频道**：目标频道。你通过上述相同的`incoming-webhook`流程授权该频道。

例如，你可以创建一个警报，当 p90 构建时长相比前 100 次构建增加超过 20% 时触发。

将缓存命中率警报限定为你的默认分支很有用，因为只有该分支会填充缓存。触及底层模块的拉取请求分支未命中缓存是正常现象，将它们包含在内会导致警报在预期的回归情况下触发。

缓存命中率警报仅比较可以公平比较的窗口。两个窗口都必须包含与滚动窗口大小一样多的运行次数，而仅出现在其中一个窗口中的缓存数据来源会被排除在外。因此，尚未积累达到滚动窗口大小两倍的运行次数的分支，或名称不匹配任何内容的分支，永远不会触发该规则。如果你将规则限定为低流量分支，请保持滚动窗口足够小，以便该分支能够填满它。

当警报触发时，你将在 Slack 频道中收到如下消息：

<img src="/images/guides/integrations/slack/alert.png" alt="显示 Slack 警报消息的图片" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> 警报触发后，同一规则在 24 小时内不会再次触发。这可以防止在指标持续偏高时产生通知疲劳。
> <!-- -->

### 不稳定测试警报 {#flaky-test-alerts}

当 Tuist 检测到新的不稳定测试时，不稳定测试警报会立即触发，帮助你在测试不稳定性影响团队之前及时发现。

要创建不稳定测试警报规则，请前往你项目的通知设置并点击**添加不稳定测试警报规则**。你可以配置：

- **名称**：警报的描述性名称
- **触发阈值**：过去 30 天内触发警报所需的不稳定运行最小次数
- **Slack 频道**：目标频道，通过`incoming-webhook`流程授权。

当测试变得不稳定并达到你的阈值时，你将收到一条通知，其中包含直接调查该测试用例的链接：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="显示 Slack 不稳定测试警报消息的图片" style="max-width: 500px;" />

## 断开集成 {#disconnect}

要停止通知，请在 Tuist 仪表板中从报告、警报规则或自动化操作中移除已配置的 Slack 频道。要完全撤销 Tuist 的访问权限，请通过**设置与管理 → 管理应用**在 Slack 内部移除 Webhook 集成。
