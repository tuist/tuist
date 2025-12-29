---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack for automated project reports."
}
---
# Slack integration {#slack}

Tuist integrates with Slack to deliver automated daily analytics reports directly to your team's channels. Stay informed about your project's build performance, cache efficiency, and bundle sizes without leaving Slack.

## Setup {#setup}

### Connect your Slack workspace {#connect-workspace}

First, connect your Slack workspace to your Tuist account in the `Integrations` tab:

![An image that shows the integrations tab with Slack connection](/images/guides/integrations/slack/integrations.png)

Click **Connect Slack** to authorize Tuist to post messages to your workspace. This will redirect you to Slack's authorization page where you can approve the connection.

### Configure project reports {#configure-reports}

After connecting Slack, configure reports for each project in the project settings:

![An image that shows the project settings with Slack report configuration](/images/guides/integrations/slack/project-settings.png)

You can configure:
- **Channel**: Select which Slack channel receives the reports
- **Schedule**: Choose which days of the week to receive reports
- **Time**: Set the time of day in your local timezone

## Daily reports {#daily-reports}

Once configured, Tuist sends automated daily reports to your selected Slack channel:

![An image that shows a Slack report message](/images/guides/integrations/slack/report.png)
