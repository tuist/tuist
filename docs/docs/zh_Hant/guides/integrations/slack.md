---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack 整合{#slack}

如果您的組織使用 Slack，您可以整合 Tuist
直接在您的頻道中顯示洞察力。這將監控從您的團隊必須記住要做的事，轉變為即時發生的事。例如，您的團隊可以收到建立效能、快取點擊率或捆綁大小趨勢的每日摘要。

## 設定{#setup}

### 連接您的 Slack 工作區{#connect-workspace}

首先，在`Integrations` 標籤中將您的 Slack 工作區連接到 Tuist 帳戶：

![顯示與 Slack 連線的整合索引標籤的影像](/images/guides/integrations/slack/integrations.png)。

按一下**Connect Slack** 授權 Tuist 在您的工作區發佈訊息。這會將您重定向到 Slack 的授權頁面，您可以在此批准連線。

> [如果您的 Slack 工作區限制安裝應用程式，您可能需要向 Slack 管理員申請批准。在授權期間，Slack 會引導您完成核准請求程序。

### 專案報告{#project-reports}

連接 Slack 後，在專案設定的通知索引標籤中設定每個專案的報告：

![顯示具有 Slack
報告設定的通知設定的影像](/images/guides/integrations/slack/notifications-settings.png)。

您可以設定：
- **頻道** ：選擇哪個 Slack 頻道會接收報告
- **排程** ：選擇每週哪幾天接收報告
- **時間**: 設定每天的時間

設定完成後，Tuist 會自動將每日報告傳送至您選定的 Slack 頻道：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### 警報規則{#alert-rules}

當關鍵指標顯著倒退時，透過警示規則在 Slack 中取得通知，協助您儘快捕捉建立速度變慢、快取效能降低或測試速度變慢等問題，將對團隊生產力的影響降至最低。

若要建立警示規則，請前往專案的通知設定，然後按一下**新增警示規則** ：

您可以設定：
- **名稱** ：警報的描述性名稱
- **分類** ：測量什麼（建立持續時間、測試持續時間或快取記憶體命中率）
- **公制**: 如何彙總資料 (p50、p90、p99 或平均值)
- **偏差** ：觸發警報的百分比變化
- **滾動視窗** ：與多少最近的運行進行比較
- **Slack 頻道** ：發送警報的位置

例如，您可以建立一個警示，當 p90 建置持續時間比前 100 次建置增加超過 20% 時就會觸發該警示。

當警報觸發時，您會在 Slack 頻道中收到類似的訊息：

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [警告觸發後，24 小時內不會再次啟動相同的規則。這可以防止某項指標持續升高時的通知疲勞。

## 現場安裝{#on-premise}

對於內部部署的 Tuist 安裝，您需要建立自己的 Slack 應用程式，並設定必要的環境變數。

### 建立 Slack 應用程式{#create-slack-app}

1. 前往 [Slack API 應用程式頁面](https://api.slack.com/apps)，然後按一下**建立新應用程式**
2. 選擇**從應用程式清單** ，然後選擇要安裝應用程式的工作區
3. 貼上下列清單，將重定向 URL 替換為您的 Tuist 伺服器 URL：

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

4. 檢視並建立應用程式

### 設定環境變數{#configure-environment}

在 Tuist 伺服器上設定下列環境變數：

- `SLACK_CLIENT_ID` - 您的 Slack 應用程式基本資訊頁面中的用戶端 ID
- `SLACK_CLIENT_SECRET` - 您的 Slack 應用程式基本資訊頁面中的用戶端秘密
