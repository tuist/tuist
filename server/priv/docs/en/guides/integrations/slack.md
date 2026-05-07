---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to use the Tuist integration for Slack."
}
---
# Tuist integration for Slack {#slack}

Tuist's integration for Slack surfaces build, test, and bundle insights directly in your channels. It turns monitoring from something your team has to remember to do into something that just happens. For example, your team can receive daily summaries of build performance, cache hit rates, or bundle size trends, and instant alerts the moment a key metric regresses or a test becomes flaky.

This page describes what the integration does, how to install it on a per-channel basis, and how Tuist handles your data. For details on how Tuist collects, manages, and stores third-party data, see our [privacy policy](https://tuist.dev/privacy).

## How the integration works {#how-it-works}

Tuist sends notifications into Slack via Slack's [Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks). The integration only requests the `incoming-webhook` scope. Each notification destination (project report, alert rule, flaky test alert, automation action) corresponds to a single Slack channel that you pick at install time. Slack creates one webhook URL per channel and Tuist stores it to deliver messages.

Tuist never reads messages, member lists, or any other data from your workspace. The integration only writes notifications into the channels you have explicitly authorized.

## Setup {#setup}

### Project reports {#project-reports}

Project reports deliver a daily summary of your project's build, test, and cache metrics into a Slack channel of your choice.

1. Open your project's notification settings in the Tuist dashboard.
2. Click **Select Slack channel** and choose the workspace and channel you want Tuist to post into. Slack will ask you to authorize the `incoming-webhook` scope and pick a single channel.
3. Choose the days of the week and the time of day you want the daily report to arrive.

![An image that shows the notifications settings with Slack report configuration](/images/guides/integrations/slack/notifications-settings.png)

Once configured, Tuist sends automated daily reports to the selected channel:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> To post into a private channel, open the channel inside Slack first and add it to the list of channels visible to the integration during the authorization step.
> <!-- -->

### Alert rules {#alert-rules}

Alert rules notify you in Slack when key metrics significantly regress, helping you catch slower builds, cache degradation, or test slowdowns as soon as possible.

To create an alert rule, go to your project's notification settings and click **Add alert rule**. You can configure:

- **Name**: A descriptive name for the alert
- **Category**: What to measure (build duration, test duration, or cache hit rate)
- **Metric**: How to aggregate the data (p50, p90, p99, or average)
- **Deviation**: The percentage change that triggers an alert
- **Rolling window**: How many recent runs to compare against
- **Slack channel**: The destination channel. You authorize the channel through the same `incoming-webhook` flow described above.

For example, you might create an alert that triggers when the p90 build duration increases by more than 20% compared to the previous 100 builds.

When an alert triggers, you'll receive a message like this in your Slack channel:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> After an alert triggers, it won't fire again for the same rule for 24 hours. This prevents notification fatigue when a metric stays elevated.
> <!-- -->

### Flaky test alerts {#flaky-test-alerts}

Flaky test alerts trigger the moment Tuist detects a new flaky test, helping you catch test instability before it impacts your team.

To create a flaky test alert rule, go to your project's notification settings and click **Add flaky test alert rule**. You can configure:

- **Name**: A descriptive name for the alert
- **Trigger threshold**: The minimum number of flaky runs in the last 30 days required to trigger an alert
- **Slack channel**: The destination channel, authorized through the `incoming-webhook` flow.

When a test becomes flaky and meets your threshold, you'll receive a notification with a direct link to investigate the test case:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## Disconnecting the integration {#disconnect}

To stop a notification, remove the configured Slack channel from the report, alert rule, or automation action in your Tuist dashboard. To revoke Tuist's access entirely, remove the webhook integration from inside Slack via **Settings & administration → Manage apps**.
