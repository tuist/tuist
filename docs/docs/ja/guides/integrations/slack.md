---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack 連携{#slack}

組織でSlackをご利用の場合、Tuistを統合することで、チャンネル内で直接インサイトを表示できます。これにより、チームが意識して行わなければならない監視作業が、自動的に行われるようになります。例えば、ビルドのパフォーマンス、キャッシュヒット率、またはバンドルサイズの傾向に関する日次サマリーをチームで受け取ることができます。

## 設定{#setup}

### Slackワークスペースを接続する{#connect-workspace}

まず、`の「Integrations」タブ（` ）で、SlackワークスペースをTuistアカウントに連携してください：

![Slack接続が設定された「統合」タブを示す画像](/images/guides/integrations/slack/integrations.png)

「**」をクリックし、「Slack**
」を接続して、Tuistがワークスペースにメッセージを投稿することを許可してください。これにより、接続を承認できるSlackの認証ページにリダイレクトされます。

> [!NOTE] SLACK 管理者の承認
> <!-- -->
> Slack ワークスペースでアプリのインストールが制限されている場合は、Slack
> 管理者に承認をリクエストする必要がある場合があります。承認リクエストの手順については、認証時に Slack が案内します。
> <!-- -->

### プロジェクト報告書{#project-reports}

Slackを連携した後、プロジェクト設定の「通知」タブで各プロジェクトのレポートを設定してください：

![Slackレポートの設定を含む通知設定画面の画像](/images/guides/integrations/slack/notifications-settings.png)

以下の設定が可能です：
- **チャンネル**: レポートを受信するSlackチャンネルを選択してください
- **** のスケジュール設定：レポートを受け取る曜日を選択してください
- **Time**: 時刻を設定する

> [!警告] プライベートチャンネル
> <!-- -->
> Tuist
> Slackアプリでプライベートチャンネルにメッセージを投稿するには、まずそのチャンネルにTuistボットを追加する必要があります。Slackでプライベートチャンネルを開き、チャンネル名をクリックして設定を開き、「統合」を選択してから「アプリを追加」を選択し、Tuistを検索してください。
> <!-- -->

設定が完了すると、Tuistは選択したSlackチャンネルに毎日自動レポートを送信します：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### アラート規則{#alert-rules}

主要な指標が大幅に悪化した場合、アラートルールを使用してSlackで通知を受け取ることで、ビルドの遅延、キャッシュの劣化、またはテストの遅延をできるだけ早く検知し、チームの生産性への影響を最小限に抑えることができます。

アラートルールを作成するには、プロジェクトの通知設定に移動し、「**」をクリックして「アラートルールを追加」を選択してください。**:

以下の設定が可能です：
- **名前** ：アラートの説明的な名前
- **カテゴリ** ：測定対象（ビルド時間、テスト時間、またはキャッシュヒット率）
- **メトリック** ：データの集計方法（p50、p90、p99、または平均）
- **偏差**: アラートをトリガーする変化率
- **** （ローリングウィンドウ）：比較対象とする直近の実行回数を指定します
- **Slackチャンネル**: アラートを送信する先

たとえば、過去100回のビルドと比較してp90ビルドの所要時間が20%以上増加した際にトリガーされるアラートを作成することができます。

アラートがトリガーされると、Slackチャンネルに次のようなメッセージが届きます：

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] クールダウン期間
> <!-- -->
> アラートがトリガーされた後、同じルールに対しては24時間以内に再度発火することはありません。これにより、メトリクスの値が高止まりしている場合の通知疲れを防ぐことができます。
> <!-- -->

### 不安定なテストアラート{#flaky-test-alerts}

テストが不安定になった際に即座に通知を受け取れます。ローリングウィンドウを比較するメトリクスベースのアラートルールとは異なり、不安定なテストのアラートは、Tuistが新しい不安定なテストを検知した瞬間にトリガーされるため、チームに影響が出る前にテストの不安定さを把握するのに役立ちます。

不安定なテストのアラートルールを作成するには、プロジェクトの通知設定に移動し、「**」をクリックします。不安定なテストのアラートルールを追加する**:

以下の設定が可能です：
- **名前** ：アラートの説明的な名前
- **トリガー閾値**: アラートをトリガーするために必要な、過去30日間の不安定な実行の最小数
- **Slackチャンネル**: アラートを送信する先

テストが不安定になり、設定した閾値に達した場合、テストケースを調査するための直接リンクが記載された通知が届きます：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## オンプレミスでのインストール{#on-premise}

オンプレミスのTuistインストール環境では、独自のSlackアプリを作成し、必要な環境変数を設定する必要があります。

### Slackアプリを作成する{#create-slack-app}

1. [Slack API Apps ページ](https://api.slack.com/apps) にアクセスし、「**」の「Create New
   App」をクリックしてください**
2. アプリマニフェスト（** ）から「**」を選択し、アプリをインストールするワークスペースを選択してください
3. 以下のマニフェストを貼り付け、リダイレクトURLをTuistサーバーのURLに置き換えてください：

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

4. アプリの確認と作成

### 環境変数の設定{#configure-environment}

Tuistサーバーで以下の環境変数を設定してください：

- `SLACK_CLIENT_ID` - Slackアプリの「基本情報」ページに記載されているクライアントID
- `SLACK_CLIENT_SECRET` - Slackアプリの「基本情報」ページにあるクライアントシークレット
