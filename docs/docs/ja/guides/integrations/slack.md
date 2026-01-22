---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack 統合{#slack}

組織でSlackを利用している場合、Tuistを統合してチャネル内で直接インサイトを可視化できます。これにより、チームが意識的に行う必要があった監視が、自動的に行われるようになります。例えば、ビルドのパフォーマンス、キャッシュヒット率、バンドルサイズの傾向に関する日次サマリーをチームが受け取ることが可能です。

## 設定{#setup}

### Slackワークスペースを接続する{#connect-workspace}

まず、`の「Integrations」タブにある「` 」で、SlackワークスペースをTuistアカウントに接続してください：

![Slack接続の統合タブを表示した画像](/images/guides/integrations/slack/integrations.png)

**をクリックし、** を接続して、Tuist がワークスペースにメッセージを投稿することを許可してください。これにより、接続を承認できる Slack
の認証ページにリダイレクトされます。

> [!NOTE] SLACK 管理者承認
> <!-- -->
> Slackワークスペースでアプリのインストールが制限されている場合、Slack管理者への承認申請が必要になる可能性があります。承認リクエストの手順は、権限付与時にSlackが案内します。
> <!-- -->

### プロジェクト報告書{#project-reports}

Slackを接続後、プロジェクト設定の通知タブで各プロジェクトのレポートを設定してください：

![Slackレポート設定を含む通知設定画面のイメージ](/images/guides/integrations/slack/notifications-settings.png)

設定可能です：
- **** チャンネル：レポートを受信するSlackチャンネルを選択
- **** のスケジュール設定：レポートを受け取る曜日を選択してください
- **時間**: 時刻を設定する

> [!WARNING] プライベートチャンネル
> <!-- -->
> Tuist
> Slackアプリがプライベートチャンネルにメッセージを投稿するには、まずそのチャンネルにTuistボットを追加する必要があります。Slackでプライベートチャンネルを開き、チャンネル名をクリックして設定を開き、「統合」を選択し、「アプリを追加」からTuistを検索してください。
> <!-- -->

設定が完了すると、Tuistは選択したSlackチャンネルに自動で日次レポートを送信します：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### アラートルール{#alert-rules}

主要メトリクスが大幅に低下した際にアラートルールでSlack通知を受け取り、ビルドの遅延、キャッシュ劣化、テストの遅延を可能な限り早期に検知し、チームの生産性への影響を最小限に抑えましょう。

アラートルールを作成するには、プロジェクトの通知設定に移動し、[**] をクリックします。アラートルールを追加**:

設定可能です：
- **** 名：アラートの説明的な名前
- **カテゴリ** ：測定対象（ビルド時間、テスト時間、またはキャッシュヒット率）
- **メトリック** ：データの集計方法（p50、p90、p99、または平均）
- **偏差** ：アラートをトリガーする変化率
- **ローリングウィンドウ**: 比較対象とする直近の実行回数を指定
- **Slackチャンネル**: アラート送信先

例：p90ビルドの所要時間が過去100回のビルドと比較して20%以上増加した場合にトリガーされるアラートを作成できます。

アラートがトリガーされると、Slackチャンネルに次のようなメッセージが届きます：

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] クールダウン期間
> <!-- -->
> アラートがトリガーされた後、同じルールでは24時間以内に再度発火しません。これにより、メトリックが上昇したままの場合でも通知疲れを防ぎます。
> <!-- -->

### 不安定なテストアラート{#flaky-test-alerts}

テストが不安定になった瞬間に通知を受け取れます。移動平均を比較するメトリックベースのアラートルールとは異なり、不安定テストアラートはTuistが新たな不安定テストを検知した瞬間に発動します。これにより、チームに影響が出る前にテストの不具合を早期に発見できます。

フラッキーテストアラートルールを作成するには、プロジェクトの通知設定に移動し、[**]をクリックします。フラッキーテストアラートルールを追加**:

設定可能です：
- **** 名：アラートの説明的な名前
- **トリガー閾値**: アラートをトリガーするために必要な、過去30日間の不安定な実行の最小回数
- **Slackチャンネル**: アラート送信先

テストが不安定になり、設定した閾値を超えた場合、テストケースを調査するための直接リンク付き通知が届きます：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## オンプレミスインストール{#on-premise}

オンプレミス版のTuistを導入する場合、独自のSlackアプリを作成し、必要な環境変数を設定する必要があります。

### Slackアプリを作成する{#create-slack-app}

1. [Slack API
   Appsページ](https://api.slack.com/apps)に移動し、[**]をクリックして新規アプリを作成してください**
2. アプリマニフェストから「**」を選択し、アプリをインストールするワークスペースを選択してください。**
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

4. アプリを確認して作成する

### 環境変数を設定する{#configure-environment}

Tuistサーバーで以下の環境変数を設定してください：

- `SLACK_CLIENT_ID` - Slackアプリの「基本情報」ページにあるクライアントID
- `SLACK_CLIENT_SECRET` - Slackアプリの「基本情報」ページにあるクライアントシークレット
