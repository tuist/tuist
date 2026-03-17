---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack 整合{#slack}

若您的組織使用 Slack，可將 Tuist
整合至其中，直接在頻道中顯示分析結果。這將使監控從團隊必須主動執行的工作，轉變為自動進行的流程。例如，您的團隊可接收關於建置效能、快取命中率或封裝大小趨勢的每日摘要。

## 設定{#setup}

### 連接您的 Slack 工作區{#connect-workspace}

首先，請在`的「整合」` 分頁中，將您的 Slack 工作區與 Tuist 帳戶連結：

![一張顯示「整合」分頁與 Slack 連線的圖片](/images/guides/integrations/slack/integrations.png)

點擊**連結 Slack** ，授權 Tuist 向您的工作區發送訊息。此操作將將您重定向至 Slack 的授權頁面，您可在該處批准此連結。

> [!NOTE] 需經 Slack 管理員核准
> <!-- -->
> 若您的 Slack 工作區限制應用程式安裝，您可能需要向 Slack 管理員申請批准。Slack 將在授權過程中引導您完成批准申請流程。
> <!-- -->

### 專案報告{#project-reports}

連接 Slack 後，請在專案設定的「通知」分頁中，為每個專案設定報告：

![一張顯示包含 Slack
報告設定的通知設定畫面圖片](/images/guides/integrations/slack/notifications-settings.png)

您可以設定：
- **頻道** ：選擇接收報告的 Slack 頻道
- **排程**: 選擇每週哪些日子接收報告
- **時間** ：設定當前時間

> [!警告] 私人頻道
> <!-- -->
> 若要讓 Tuist Slack 應用程式在私人頻道中發送訊息，您必須先將 Tuist 機器人加入該頻道。在 Slack
> 中，開啟私人頻道，點擊頻道名稱以開啟設定，選擇「整合」，接著點選「新增應用程式」並搜尋 Tuist。
> <!-- -->

設定完成後，Tuist 會將自動生成的每日報告發送至您指定的 Slack 頻道：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### 警示規則{#alert-rules}

透過 Slack 的警示規則，當關鍵指標出現顯著惡化時接收通知，協助您盡早發現建置速度變慢、快取效能下降或測試速度變慢等狀況，從而將對團隊生產力的影響降至最低。

要建立警示規則，請前往專案的通知設定，並點擊**Add alert rule**:

您可以設定：
- **名稱**: 用於描述該警示的名稱
- **分類：** ：應測量哪些指標（建置時間、測試時間或快取命中率）
- **指標** ：如何彙總數據（p50、p90、p99 或平均值）
- **偏差**: 觸發警示的百分比變化
- **滾動視窗**: 需拿來比對的最近執行次數
- **Slack 頻道** ：警示訊息應發送至此處

例如，您可以建立一個警示，當 p90 的建置時間與前 100 次建置相比增加超過 20% 時觸發。

當警報觸發時，您將在 Slack 頻道中收到類似以下的訊息：

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] 冷卻期
> <!-- -->
> 警報觸發後，同一規則在 24 小時內不會再次觸發。此舉可避免在指標持續偏高時造成通知疲勞。
> <!-- -->

### 不穩定的測試警示{#flaky-test-alerts}

當測試出現不穩定狀況時，立即收到通知。與比較滾動視窗的指標型警示規則不同，不穩定測試警示會在 Tuist
偵測到新的不穩定測試時立即觸發，協助您在測試不穩定性影響團隊之前及時發現問題。

若要建立不穩定測試警示規則，請前往專案的通知設定，並點擊「**」新增不穩定測試警示規則**:

您可以設定：
- **名稱**: 用於描述該警示的名稱
- **觸發閾值**: 過去 30 天內觸發警示所需的最低不穩定執行次數
- **Slack 頻道** ：警示訊息應發送至此處

當測試變得不穩定且達到您的閾值時，您將收到一則通知，其中包含直接連結以便您調查該測試案例：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## 本地部署{#on-premise}

對於本地部署的 Tuist 安裝，您需要自行建立 Slack 應用程式並設定必要的環境變數。

### 建立 Slack 應用程式{#create-slack-app}

1. 前往 [Slack API Apps 頁面](https://api.slack.com/apps)，並點擊「**」建立新應用程式**
2. 從應用程式清單** 中選擇「**」，並選取您要安裝應用程式的工作區
3. 請貼上以下清單，並將重定向網址替換為您的 Tuist 伺服器網址：

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

請在您的 Tuist 伺服器上設定以下環境變數：

- `SLACK_CLIENT_ID` - 來自您的 Slack 應用程式「基本資訊」頁面的 Client ID
- `SLACK_CLIENT_SECRET` - 來自您的 Slack 應用程式「基本資訊」頁面的 Client Secret
