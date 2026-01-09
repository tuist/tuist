---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slackとの統合{#slack}

もしあなたの組織がSlackを使っているなら、Tuistを統合して、チャンネルに直接インサイトを表示することができる。これにより、モニタリングは、チームが忘れずに行わなければならないものから、ただ行われるものに変わります。例えば、ビルド・パフォーマンス、キャッシュ・ヒット率、バンドル・サイズの傾向などのサマリーを毎日受け取ることができます。

## セットアップ{#setup}

### Slackワークスペースに接続する{#connect-workspace}

まず、`Integrations` タブで、SlackワークスペースをTuistアカウントに接続する：

![Slack接続と統合タブを示す画像](/images/guides/integrations/slack/integrations.png)。

**Connect Slack**
をクリックして、Tuistがあなたのワークスペースにメッセージを投稿することを承認する。Slackの認証ページにリダイレクトされ、接続を承認することができます。

> [注意] SLACK ADMIN APPROVAL
> Slackワークスペースがアプリのインストールを制限している場合、Slack管理者に承認をリクエストする必要がある場合があります。Slackは承認時に承認リクエストプロセスを案内します。

### プロジェクト報告{#project-reports}

After connecting Slack, configure reports for each project in the project
settings' notifications tab:

![An image that shows the notifications settings with Slack report
configuration](/images/guides/integrations/slack/notifications-settings.png)

設定できる：
- **チャンネル** ：レポートを受信するSlackチャンネルを選択する
- **スケジュール** ：レポートを受信する曜日を選択
- **Time**: 一日の時間を設定する

一度設定すると、Tuistは選択したSlackチャンネルに自動デイリーレポートを送信する：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Alert rules {#alert-rules}

Get notified in Slack with alert rules when key metrics significantly regress to
help you catch slower builds, cache degradation, or test slowdowns as soon as
possible, minimizing the impact on your team's productivity.

To create an alert rule, go to your project's notification settings and click
**Add alert rule**:

設定できる：
- **Name**: A descriptive name for the alert
- **Category**: What to measure (build duration, test duration, or cache hit
  rate)
- **Metric**: How to aggregate the data (p50, p90, p99, or average)
- **Deviation**: The percentage change that triggers an alert
- **Rolling window**: How many recent runs to compare against
- **Slack channel**: Where to send the alert

For example, you might create an alert that triggers when the p90 build duration
increases by more than 20% compared to the previous 100 builds.

When an alert triggers, you'll receive a message like this in your Slack
channel:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD After an alert triggers, it won't fire again for the
> same rule for 24 hours. This prevents notification fatigue when a metric stays
> elevated.

## オンプレミス・インストール{#on-premise}

オンプレミスのTuistをインストールする場合は、独自のSlackアプリを作成し、必要な環境変数を設定する必要があります。

### Slackアプリの作成{#create-slack-app}

1. Slack API Appsページ](https://api.slack.com/apps)にアクセスし、**Create New
   Appsをクリックします。**
2. **アプリマニフェストから** を選択し、アプリをインストールするワークスペースを選択します。
3. リダイレクト URL をあなたの Tuist サーバー URL に置き換えて、以下のマニフェストを貼り付けます：

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

4. アプリのレビューと作成

### 環境変数の設定{#configure-environment}

Tuistサーバーで以下の環境変数を設定する：

- `SLACK_CLIENT_ID` - Slackアプリの基本情報ページにあるクライアントID。
- `SLACK_CLIENT_SECRET` - Slackアプリの基本情報ページにあるクライアントシークレット。
