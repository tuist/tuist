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

Slackに接続したら、プロジェクト設定の通知タブでプロジェクトごとにレポートを設定する：

Slackのレポート設定で通知設定を示す画像](/images/guides/integrations/slack/notifications-settings.png)。

設定できる：
- **チャンネル** ：レポートを受信するSlackチャンネルを選択する
- **スケジュール** ：レポートを受信する曜日を選択
- **Time**: 一日の時間を設定する

一度設定すると、Tuistは選択したSlackチャンネルに自動デイリーレポートを送信する：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### 警報規則{#alert-rules}

主要なメトリクスが著しく低下した場合、アラートルールによってSlackに通知されるため、ビルドの遅延、キャッシュの劣化、テストのスローダウンをいち早くキャッチし、チームの生産性への影響を最小限に抑えることができます。

アラートルールを作成するには、プロジェクトの通知設定に移動し、**アラートルールの追加** をクリックします：

設定できる：
- **名前** ：アラートの説明的な名前
- **カテゴリー** ：何を測定するか（ビルド期間、テスト期間、キャッシュヒット率）
- **Metric**: データの集計方法（p50、p90、p99、または平均値）
- **偏差** ：アラートのトリガーとなる変化率
- **ローリングウィンドウ** ：比較する最近の実行回数
- **Slackチャンネル** ：アラートの送信先

例えば、p90のビルド期間が以前の100ビルドと比較して20％以上増加したときにトリガーされるアラートを作成することができます。

アラートがトリガーされると、Slackチャンネルにこのようなメッセージが届きます：

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [注意] クールダウン期間
> アラートがトリガーされた後、24時間は同じルールで再度発火しません。これにより、指標が上昇し続けた場合の通知疲れを防ぐことができます。

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
