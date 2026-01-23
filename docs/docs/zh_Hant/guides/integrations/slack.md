---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack 整合{#slack}

若貴組織使用 Slack，可整合 Tuist
將分析結果直接顯示於通訊頻道。此舉能將監控從團隊需主動執行的任務，轉變為自動運作的機制。舉例而言，團隊可接收每日彙整的建置效能、快取命中率或封裝大小趨勢報告。

## 設定{#setup}

### 連接您的 Slack 工作區{#connect-workspace}

首先，請在`整合功能` 標籤頁中，將您的 Slack 工作空間與 Tuist 帳戶連結：

![顯示整合標籤頁與 Slack 連接的圖片](/images/guides/integrations/slack/integrations.png)

點擊**連結 Slack** 以授權 Tuist 向您的工作空間發佈訊息。此操作將導向 Slack 授權頁面，您可於該處批准此連結。

> [!注意] 需經 Slack 管理員核准
> <!-- -->
> 若您的 Slack 工作區限制應用程式安裝，您可能需要向 Slack 管理員申請批准。授權過程中，Slack 將引導您完成批准申請流程。
> <!-- -->

### 專案報告{#project-reports}

連接 Slack 後，請至專案設定的「通知」分頁為每個專案設定報告：

![顯示通知設定與 Slack
報告配置的圖片](/images/guides/integrations/slack/notifications-settings.png)

您可設定：
- **頻道**: 選擇接收報告的 Slack 通道
- **排程**: 選擇每週接收報告的日期
- **時間設定：**

> [!警告] 私人頻道
> <!-- -->
> 若要讓 Tuist Slack 應用程式在私人頻道發佈訊息，您必須先將 Tuist 機器人加入該頻道。請在 Slack
> 中開啟私人頻道，點擊頻道名稱開啟設定，選擇「整合」後點選「新增應用程式」，搜尋 Tuist 即可。
> <!-- -->

設定完成後，Tuist 將自動每日向您指定的 Slack 通道發送報告：

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### 警示規則{#alert-rules}

透過警示規則在 Slack 接收通知，當關鍵指標出現顯著退化時，協助您盡快發現建置速度變慢、快取效能衰退或測試延遲等狀況，將對團隊生產力的影響降至最低。

若要建立警示規則，請前往專案的通知設定，點擊「新增警示規則」連結：**Add alert rule**:

您可設定：
- **名稱**: 警報的描述性名稱
- **類別** ：應測量項目（建置時間、測試時間或快取命中率）
- **指標** ：數據聚合方式（第50百分位數、第90百分位數、第99百分位數或平均值）
- **偏差**: 觸發警報的百分比變化值
- **滾動視窗**: 需對比多少次近期執行結果
- **Slack 通道**: 警報發送位置

例如，您可建立一個警示，當 p90 建造時間較前 100 次建造增加超過 20% 時觸發。

當警報觸發時，您將在 Slack 通道收到類似以下訊息：

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!注意] 冷卻期
> <!-- -->
> 警報觸發後，相同規則將在24小時內不再觸發。此機制可避免指標持續偏高時引發的通知疲勞。
> <!-- -->

### 不穩定測試警報{#flaky-test-alerts}

當測試出現不穩定時立即接收通知。不同於基於指標的警報規則（需比較滾動視窗數據），不穩定測試警報會在 Tuist
偵測到新不穩定測試時立即觸發，助您在測試不穩定影響團隊前及時發現問題。

若要建立不穩定測試警示規則，請前往專案的通知設定，點擊「新增不穩定測試警示規則」連結：**Add flaky test alert rule**

您可設定：
- **名稱**: 警報的描述性名稱
- **觸發閾值**: 過去30天內觸發警報所需的最低不穩定運行次數
- **Slack 通道**: 警報發送位置

當測試變得不穩定且達到設定閾值時，您將收到通知並附有直接連結以調查該測試案例：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## 本地安裝{#on-premise}

針對本地部署的 Tuist 安裝，您需要自行建立 Slack 應用程式並設定必要的環境變數。

### 建立 Slack 應用程式{#create-slack-app}

1. 前往 [Slack API 應用程式頁面](https://api.slack.com/apps)，點擊「建立新應用程式」****
2. 從應用程式清單中選擇「**」** ，並選取欲安裝應用程式的作業區
3. 請將以下清單貼上，並將重定向網址替換為您的 Tuist 伺服器網址：

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

4. 審核並建立應用程式

### 設定環境變數{#configure-environment}

請在您的 Tuist 伺服器上設定以下環境變數：

- `SLACK_CLIENT_ID` - 取自您的 Slack 應用程式「基本資訊」頁面的客戶端 ID
- `SLACK_CLIENT_SECRET` - 取自您的 Slack 應用程式「基本資訊」頁面的客戶端密鑰
