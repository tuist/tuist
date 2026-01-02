---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack 整合{#slack}

如果您的组织使用 Slack，您可以集成
Tuist，直接在您的渠道中显示洞察力。这就将监控从团队必须记住的事情变成了直接发生的事情。例如，您的团队可以收到有关构建性能、缓存命中率或捆绑包大小趋势的每日摘要。

## 设置{#setup}

### 连接您的 Slack 工作区{#connect-workspace}

首先，在`Integrations` 标签中将 Slack 工作区连接到 Tuist 账户：

![显示带有 Slack 连接的集成选项卡的图片](/images/guides/integrations/slack/integrations.png)。

单击**Connect Slack** 授权 Tuist 在您的工作区发布消息。这会将您重定向到 Slack 的授权页面，您可以在那里批准连接。

> [如果您的 Slack 工作区限制安装应用程序，您可能需要向 Slack 管理员申请批准。在授权过程中，Slack 将指导您完成审批请求流程。

### 项目报告{#project-reports}

连接 Slack 后，在项目设置中为每个项目配置报告：

![显示带有 Slack
报告配置的项目设置的图片](/images/guides/integrations/slack/project-settings.png)。

您可以配置
- **频道** ：选择接收报告的 Slack 频道
- **时间表** ：选择每周哪几天接收报告
- **时间** ：设置一天中的时间

配置完成后，Tuist 会向您选择的 Slack 频道自动发送每日报告：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

## 内部安装{#on-premise}

对于内部安装的 Tuist，您需要创建自己的 Slack 应用程序并配置必要的环境变量。

### 创建 Slack 应用程序{#create-slack-app}

1. 转到 [Slack API 应用程序页面](https://api.slack.com/apps)，然后单击**创建新应用程序**
2. 选择**从应用程序清单** 并选择要安装应用程序的工作区
3. 粘贴以下清单，将重定向 URL 替换为 Tuist 服务器 URL：

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
                "channels:read",
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

4. 审查和创建应用程序

### 配置环境变量{#configure-environment}

在 Tuist 服务器上设置以下环境变量：

- `SLACK_CLIENT_ID` - 您的 Slack 应用程序 "基本信息 "页面中的客户端 ID
- `SLACK_CLIENT_SECRET` - 您的 Slack 应用程序 "基本信息 "页面中的客户秘密
