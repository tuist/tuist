---
{
  "title": "Slack",
  "titleTemplate": ":title | 集成 | 指南 | Tuist",
  "description": "了解如何使用 Tuist 的 Slack 集成。"
}
---
# Tuist 的 Slack 集成 {#slack}

Tuist 的 Slack 集成将构建、测试和包体积洞察直接呈现到你的频道中。它将监控从团队需要刻意记住去做的事情，转变为自动发生的过程。例如，你的团队可以接收关于构建性能、缓存命中率或包体积趋势的每日摘要，并在关键指标出现退化或测试变得不稳定时立即收到警报。

本页介绍该集成的功能、如何按频道安装，以及 Tuist 如何处理你的数据。有关 Tuist 如何收集、管理和存储第三方数据的详细信息，请参阅我们的[隐私政策](https://tuist.dev/privacy)。

## 集成工作原理 {#how-it-works}

Tuist 通过 Slack 的[Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks)向 Slack 发送通知。该集成仅请求`incoming-webhook`作用域。每个通知目标（项目报告、告警规则、不稳定测试告警、自动化操作）对应你在安装时选择的一个 Slack 频道。Slack 为每个频道创建一个 webhook URL，Tuist 会存储该 URL 以发送消息。

Tuist 绝不会读取你工作区中的消息、成员列表或任何其他数据。该集成仅向你明确授权的频道写入通知。

## 设置 {#setup}

### 项目报告 {#project-reports}

项目报告会将你的项目的构建、测试和缓存指标的每日摘要发送到你选择的 Slack 频道。

1. 在 Tuist 仪表板中打开你项目的通知设置。
2. 点击**选择 Slack 频道**，并选择你希望 Tuist 发布消息的工作区和频道。Slack 会要求你授权`incoming-webhook`作用域并选择一个频道。
3. 选择你希望接收每日报告的星期几和具体时间。

![显示包含 Slack 报告配置的通知设置的图片](/images/guides/integrations/slack/notifications-settings.png)

配置完成后，Tuist 会向所选频道发送自动每日报告：

<img src="/images/guides/integrations/slack/report.png" alt="显示 Slack 报告消息的图片" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> 要向私有频道发布消息，请先在 Slack 中打开该频道，并在授权步骤中将其添加到集成可见的频道列表中。
> <!-- -->

### 告警规则 {#alert-rules}

当关键指标显著退化时，告警规则会在 Slack 中通知你，帮助你尽快发现构建变慢、缓存退化或测试变慢的情况。

要创建告警规则，请前往你项目的通知设置并点击**添加告警规则**。你可以配置：

- **名称**：告警的描述性名称
- **类别**：要测量的内容（构建时长、测试时长、缓存命中率或包体积）
- **指标**：如何聚合数据（p50、p90、p99 或平均值）
- **偏差**：触发告警的百分比变化
- **滚动窗口**：用于比较的最近运行次数
- **分支**：对于缓存命中率告警，将比较限制为单个分支上的运行。留空则考虑所有分支。包体积告警始终针对单个分支。
- **Slack 频道**：目标频道。你通过上述相同的`incoming-webhook`流程授权该频道。

例如，你可以创建一个告警，当 p90 构建时长相比前 100 次构建增加超过 20% 时触发。

将缓存命中率告警限定为你的默认分支很有用，因为只有该分支会填充缓存。触及底层模块的拉取请求分支会合理地错过缓存，如果将它们包括在内，会导致告警在预期的退化情况下触发。

缓存命中率告警只会公平地比较可比较的窗口。两个窗口都必须包含与滚动窗口大小相同数量的运行，并且仅出现在其中一个窗口中的缓存数据来源会被排除在两者之外。因此，尚未积累达到滚动窗口大小两倍的运行次数的分支，或名称不匹配任何内容的分支，永远不会触发该规则。如果你将规则限定到低流量分支，请将滚动窗口设置得足够小，以便该分支能够填满它。

当告警触发时，你会在 Slack 频道中收到如下消息：

<img src="/images/guides/integrations/slack/alert.png" alt="显示 Slack 告警消息的图片" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> 告警触发后，同一规则在 24 小时内不会再次触发。这可以防止在指标持续偏高时产生通知疲劳。
> <!-- -->

### 不稳定测试告警 {#flaky-test-alerts}

当 Tuist 检测到新的不稳定测试时，不稳定测试告警会立即触发，帮助你在测试不稳定性影响团队之前及时发现。

要创建不稳定测试告警规则，请前往你项目的通知设置并点击**添加不稳定测试告警规则**。你可以配置：

- **名称**：告警的描述性名称
- **触发阈值**：过去 30 天内触发告警所需的不稳定运行的最小数量
- **Slack 频道**：目标频道，通过`incoming-webhook`流程授权。

当测试变得不稳定并达到你的阈值时，你将收到一条包含直接链接的通知，以便调查该测试用例：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="显示 Slack 不稳定测试告警消息的图片" style="max-width: 500px;" />

## 断开集成 {#disconnect}

要停止通知，请在 Tuist 仪表板中从报告、告警规则或自动化操作中移除已配置的 Slack 频道。要完全撤销 Tuist 的访问权限，请通过**设置与管理 → 管理应用**在 Slack 内部移除 Webhook 集成。
