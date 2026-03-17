---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack 集成{#slack}

如果贵组织使用 Slack，您可以集成
Tuist，将洞察直接展示在频道中。这将使监控从团队需要主动执行的任务，转变为自动发生的流程。例如，您的团队可以接收构建性能、缓存命中率或打包大小趋势的每日摘要。

## 设置{#setup}

### 连接您的 Slack 工作区{#connect-workspace}

首先，在`的“集成”` 选项卡中，将您的 Slack 工作区与 Tuist 账户连接：

![一张展示“集成”选项卡中 Slack 连接的图片](/images/guides/integrations/slack/integrations.png)

点击**连接 Slack** ，授权 Tuist 向您的工作区发布消息。这将重定向至 Slack 的授权页面，您可在该页面批准此连接。

> [!NOTE] 需经 Slack 管理员批准
> <!-- -->
> 如果您的 Slack 工作区限制应用安装，您可能需要向 Slack 管理员申请批准。在授权过程中，Slack 将引导您完成批准申请流程。
> <!-- -->

### 项目报告{#project-reports}

连接 Slack 后，请在项目设置的“通知”选项卡中为每个项目配置报告：

![一张展示包含 Slack
报告配置的通知设置的图片](/images/guides/integrations/slack/notifications-settings.png)

您可以配置：
- **频道** ：选择接收报告的 Slack 频道
- **** 计划任务：选择每周接收报告的具体日期
- **Time**: 设置时间

> [!警告] 私人频道
> <!-- -->
> 若要在 Tuist Slack 应用中向私有频道发布消息，您必须先将 Tuist 机器人添加到该频道。在 Slack
> 中，打开私有频道，点击频道名称进入设置，选择“集成”，然后点击“添加应用”并搜索 Tuist。
> <!-- -->

配置完成后，Tuist 会将自动生成的每日报告发送至您指定的 Slack 频道：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### 提示规则{#alert-rules}

通过警报规则在 Slack 中接收通知，当关键指标出现显著恶化时，帮助您尽早发现构建变慢、缓存退化或测试变慢等问题，从而最大限度地减少对团队生产力的影响。

要创建警报规则，请前往项目的通知设置，点击**Add alert rule**:

您可以配置：
- **名称** ：用于描述该警报的名称
- **分类：** ：应测量什么（构建时长、测试时长还是缓存命中率）
- **指标** ：如何聚合数据（p50、p90、p99 或平均值）
- **偏差**: 触发警报的百分比变化
- **滚动窗口**: 用于比较的最近运行次数
- **Slack 频道** ：警报发送地址

例如，您可以创建一个警报，当 p90 的构建时长与前 100 次构建相比增加超过 20% 时触发。

当警报触发时，您将在 Slack 频道中收到如下消息：

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] 冷却期
> <!-- -->
> 警报触发后，24 小时内同一规则不会再次触发。这可以避免指标持续处于高位时出现通知疲劳。
> <!-- -->

### 测试警报不稳定{#flaky-test-alerts}

当测试出现不稳定情况时，您将立即收到通知。与基于指标且需比较滚动窗口的警报规则不同，Tuist
会在检测到新的不稳定测试的瞬间触发警报，帮助您在测试不稳定影响团队之前及时发现问题。

要创建不稳定测试警报规则，请前往项目的通知设置，点击“**”添加不稳定测试警报规则**:

您可以配置：
- **名称** ：用于描述该警报的名称
- **触发阈值**: 过去 30 天内触发警报所需的最小不稳定运行次数
- **Slack 频道** ：警报发送地址

当测试出现不稳定情况并达到您的阈值时，您将收到一条通知，其中包含一个直接链接，可用于排查该测试用例：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## 本地部署{#on-premise}

对于本地部署的 Tuist 安装，您需要创建自己的 Slack 应用并配置必要的环境变量。

### 创建一个 Slack 应用{#create-slack-app}

1. 访问 [Slack API 应用页面](https://api.slack.com/apps)，点击“**”创建新应用**
2. 从应用清单** 中选择“**”，并选择您要安装应用的工作区
3. 粘贴以下清单，并将重定向 URL 替换为您的 Tuist 服务器 URL：

```json
{
    "display_information": {
        "name": "Tuist",
        "description": "Get regular updates and alerts for your builds, tests, and caching.",
        "background_color": "#6f2cff"
    },
    "features": {
        "bot_user": {
            "display_name": "Tuist",
            "always_online": false
        }
    },
    "oauth_config": {
        "redirect_urls": [
            "https://your-tuist-server.com/integrations/slack/callback"
        ],
        "scopes": {
            "bot": [
                "chat:write",
                "chat:write.public"
            ]
        }
    },
    "settings": {
        "org_deploy_enabled": false,
        "socket_mode_enabled": false,
        "token_rotation_enabled": false
    }
}
```

4. 审核并创建应用

### 配置环境变量{#configure-environment}

请在您的 Tuist 服务器上设置以下环境变量：

- `SLACK_CLIENT_ID` - 来自您的 Slack 应用“基本信息”页面的客户端 ID
- `SLACK_CLIENT_SECRET` - 来自您的 Slack 应用“基本信息”页面的客户端密钥
