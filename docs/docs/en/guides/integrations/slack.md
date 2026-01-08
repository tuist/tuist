---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack integration {#slack}

If your organization uses Slack, you can integrate Tuist to surface insights directly in your channels. This turns monitoring from something your team has to remember to do into something that just happens. For example, your team can receive daily summaries of build performance, cache hit rates, or bundle size trends.

## Setup {#setup}

### Connect your Slack workspace {#connect-workspace}

First, connect your Slack workspace to your Tuist account in the `Integrations` tab:

![An image that shows the integrations tab with Slack connection](/images/guides/integrations/slack/integrations.png)

Click **Connect Slack** to authorize Tuist to post messages to your workspace. This will redirect you to Slack's authorization page where you can approve the connection.

> [!NOTE] SLACK ADMIN APPROVAL
> If your Slack workspace restricts app installations, you may need to request approval from a Slack administrator. Slack will guide you through the approval request process during authorization.

### Project reports {#project-reports}

After connecting Slack, configure reports for each project in the project settings:

![An image that shows the project settings with Slack report configuration](/images/guides/integrations/slack/project-settings.png)

You can configure:
- **Channel**: Select which Slack channel receives the reports
- **Schedule**: Choose which days of the week to receive reports
- **Time**: Set the time of day

Once configured, Tuist sends automated daily reports to your selected Slack channel:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

## On-premise installations {#on-premise}

For on-premise Tuist installations, you'll need to create your own Slack app and configure the necessary environment variables.

### Create a Slack app {#create-slack-app}

1. Go to the [Slack API Apps page](https://api.slack.com/apps) and click **Create New App**
2. Choose **From an app manifest** and select the workspace where you want to install the app
3. Paste the following manifest, replacing the redirect URL with your Tuist server URL:

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

4. Review and create the app

### Configure environment variables {#configure-environment}

Set the following environment variables on your Tuist server:

- `SLACK_CLIENT_ID` - The Client ID from your Slack app's Basic Information page
- `SLACK_CLIENT_SECRET` - The Client Secret from your Slack app's Basic Information page
