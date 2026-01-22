---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack集成{#slack}

若贵组织使用Slack，可集成Tuist将洞察直接推送至频道。这将监控从团队需主动执行的任务转变为自动进行的流程。例如，团队可接收每日构建性能摘要、缓存命中率报告或包体积趋势分析。

## 设置{#setup}

### 连接您的 Slack 工作区{#connect-workspace}

首先，在`的"集成"选项卡中将您的Slack工作区连接至Tuist账户：`

![显示集成选项卡中Slack连接的图片](/images/guides/integrations/slack/integrations.png)

点击**Connect Slack** 授权 Tuist 向您的工作区发布消息。这将重定向至 Slack 授权页面，您可在该页面批准连接。

> [!注意] 需经Slack管理员批准
> <!-- -->
> 若您的 Slack 工作区限制应用安装，可能需要向 Slack 管理员申请批准。授权过程中 Slack 将引导您完成审批请求流程。
> <!-- -->

### 项目报告{#project-reports}

连接 Slack 后，请在项目设置的“通知”选项卡中为每个项目配置报告：

![一张展示通知设置与Slack报告配置的图片](/images/guides/integrations/slack/notifications-settings.png)

可配置选项：
- **频道** ：选择接收报告的Slack频道
- **** ：选择每周接收报告的日期
- **时间**: 设置时间

> [!WARNING] 私人频道
> <!-- -->
> 若要让 Tuist Slack 应用在私有频道中发布消息，您必须先将 Tuist 机器人添加至该频道。在 Slack
> 中打开私有频道，点击频道名称进入设置，选择"集成"，然后点击"添加应用"并搜索 Tuist。
> <!-- -->

配置完成后，Tuist将自动向您选定的Slack频道发送每日报告：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### 警报规则{#alert-rules}

通过Slack的警报规则获取关键指标显著退化的通知，助您及时发现构建变慢、缓存降级或测试延迟等问题，最大限度减少对团队效率的影响。

创建警报规则时，请前往项目通知设置，点击**添加警报规则**:

可配置选项：
- **名称**: 警报的描述性名称
- **分类** ：需衡量的指标（构建时长、测试时长或缓存命中率）
- **指标** ：数据聚合方式（p50、p90、p99或平均值）
- **偏差** ：触发警报的百分比变化值
- **滚动窗口** ：用于比较的最近运行次数
- **Slack频道** ：警报发送地址

例如，您可能创建一个警报，当 p90 构建时长与前 100 次构建相比增加超过 20% 时触发。

当警报触发时，您将在Slack频道收到如下消息：

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!注意] 冷却期
> <!-- -->
> 警报触发后，同一规则将在24小时内不再触发。此机制可避免指标持续异常时引发的通知疲劳。
> <!-- -->

### 不稳定的测试警报{#flaky-test-alerts}

当测试出现不稳定时立即收到通知。不同于基于指标的滚动窗口警报规则，不稳定测试警报会在Tuist检测到新不稳定测试时立即触发，助您在影响团队前及时发现测试不稳定问题。

要创建不稳定测试警报规则，请前往项目通知设置，点击**添加不稳定测试警报规则**:

可配置选项：
- **名称**: 警报的描述性名称
- **触发阈值** ：过去30天内触发警报所需的最小不稳定运行次数
- **Slack频道** ：警报发送地址

当测试用例出现不稳定且达到阈值时，您将收到通知，其中包含直接链接以便调查该测试用例：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## 本地部署{#on-premise}

对于本地部署的 Tuist 安装，您需要创建自己的 Slack 应用并配置必要的环境变量。

### 创建 Slack 应用{#create-slack-app}

1. 前往[Slack API Apps页面](https://api.slack.com/apps)，点击**创建新应用**
2. 从应用程序清单中选择**，访问** 并选择要安装应用的工作区
3. 粘贴以下清单文件，并将重定向网址替换为您的Tuist服务器网址：

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

在您的 Tuist 服务器上设置以下环境变量：

- `SLACK_CLIENT_ID` - 来自您的 Slack 应用基本信息页面的客户端 ID
- `SLACK_CLIENT_SECRET` - 来自您的 Slack 应用程序基本信息页面的客户端密钥
