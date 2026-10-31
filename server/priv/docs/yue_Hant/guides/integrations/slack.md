---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "了解如何使用 Tuist 的 Slack 整合功能。"
}
---
# Tuist 嘅 Slack 整合 {#slack}

Tuist 嘅 Slack 整合會將構建、測試同捆綁包洞察直接顯示喺你嘅頻道入面。佢將監控由團隊需要記住去做嘅事，變成自動發生嘅事。例如，你嘅團隊可以收到每日構建效能、快取命中率或捆綁包大小趨勢嘅摘要，以及當關鍵指標倒退或測試變得不穩定時嘅即時警報。

此頁面說明整合功能、如何按頻道安裝，以及 Tuist 點樣處理你嘅數據。有關 Tuist 點樣收集、管理同儲存第三方數據嘅詳情，請參閱我哋嘅 [私隱政策](https://tuist.dev/privacy)。

## 整合運作方式 {#how-it-works}

Tuist 透過 Slack 嘅 [Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks) 向 Slack 發送通知。該整合只請求 `incoming-webhook` 權限範圍。每個通知目的地（項目報告、警報規則、不穩定測試警報、自動化動作）對應一個你喺安裝時選擇嘅 Slack 頻道。Slack 會為每個頻道建立一個 webhook URL，而 Tuist 會儲存佢嚟傳送訊息。

Tuist 永遠唔會讀取你工作區嘅訊息、成員列表或任何其他數據。該整合只會向你明確授權嘅頻道寫入通知。

## 設定 {#setup}

### 項目報告 {#project-reports}

項目報告會將你項目嘅構建、測試同快取指標每日摘要發送到你選擇嘅 Slack 頻道。

1. 喺 Tuist 儀表板中打開你項目嘅通知設定。
2. 點擊 **選擇 Slack 頻道** 並選擇你想讓 Tuist 發布內容嘅工作區同頻道。Slack 會要求你授權 `incoming-webhook` 權限範圍並選擇單一頻道。
3. 選擇你希望每日報告到達嘅星期幾同時間。

![顯示包含 Slack 報告配置嘅通知設定嘅圖片](/images/guides/integrations/slack/notifications-settings.png)

設定完成後，Tuist 會向所選頻道發送自動每日報告：

<img src="/images/guides/integrations/slack/report.png" alt="顯示 Slack 報告訊息嘅圖片" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> 要發布到私人頻道，請先喺 Slack 內打開該頻道，並喺授權步驟期間將其添加到整合可見嘅頻道列表中。
> <!-- -->

### 警報規則 {#alert-rules}

當關鍵指標顯著倒退時，警報規則會喺 Slack 中通知你，幫助你盡快發現構建變慢、快取退化或測試減速嘅情況。

要建立警報規則，請前往你項目嘅通知設定並點擊 **新增警報規則**。你可以配置：

- **名稱**：警報嘅描述性名稱
- **類別**：要測量嘅內容（構建持續時間、測試持續時間、快取命中率或捆綁包大小）
- **指標**：點樣聚合數據（p50、p90、p99 或平均值）
- **偏差**：觸發警報嘅百分比變化
- **滾動窗口**：要比較嘅最近運行次數
- **分支**：對於快取命中率警報，將比較限制喺單一分支上嘅運行。留空以考慮所有分支。捆綁包大小警報始終針對單一分支。
- **Slack 頻道**：目標頻道。你透過上述相同嘅 `incoming-webhook` 流程授權該頻道。

例如，你可以建立一個警報，當 p90 構建持續時間相比之前 100 次構建增加超過 20% 時觸發。

將快取命中率警報限定於你嘅預設分支係有用嘅，因為只有該分支會填充快取。觸及底層模組嘅拉取請求分支合理地錯過快取，包含佢哋會導致警報喺預期嘅倒退時觸發。

快取命中率警報只比較佢可以公平比較嘅窗口。兩個窗口都必須包含等同於滾動窗口大小嘅運行次數，而只出現喺其中一個窗口中嘅快取數據來源會被排除喺兩者之外。因此，尚未累積足夠兩次滾動窗口大小運行次數嘅分支，或名稱無匹配任何內容嘅分支，永遠唔會觸發規則。如果你將規則限定於低流量分支，請保持滾動窗口足夠小，以便該分支可以填滿佢。

當警報觸發時，你會喺 Slack 頻道中收到類似以下嘅訊息：

<img src="/images/guides/integrations/slack/alert.png" alt="顯示 Slack 警報訊息嘅圖片" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> 警報觸發後，同一規則喺 24 小時內唔會再次觸發。這防止咗當指標持續偏高時嘅通知疲勞。
> <!-- -->

### 不穩定測試警報 {#flaky-test-alerts}

當 Tuist 檢測到新嘅不穩定測試時，不穩定測試警報會立即觸發，幫助你喺影響團隊之前發現測試不穩定性。

要建立不穩定測試警報規則，請前往你項目嘅通知設定並點擊 **新增不穩定測試警報規則**。你可以配置：

- **名稱**：警報嘅描述性名稱
- **觸發閾值**：過去 30 天內觸發警報所需嘅最少不穩定運行次數
- **Slack 頻道**：目標頻道，透過 `incoming-webhook` 流程授權。

當測試變得不穩定並達到你嘅閾值時，你會收到一條帶有直接鏈接嘅通知，以便調查測試案例：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="顯示 Slack 不穩定測試警報訊息嘅圖片" style="max-width: 500px;" />

## 停用整合 {#disconnect}

要停止通知，請從 Tuist 儀表板中嘅報告、警報規則或自動化動作移除已配置嘅 Slack 頻道。要完全撤銷 Tuist 嘅訪問權限，請透過 **設定與管理 → 管理應用程式** 從 Slack 內部移除 webhook 整合。
