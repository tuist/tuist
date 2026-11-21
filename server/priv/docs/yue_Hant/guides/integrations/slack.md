---
{
  "title": "Slack",
  "titleTemplate": ":title | 整合 | 指南 | Tuist",
  "description": "了解如何使用 Tuist 的 Slack 整合。"
}
---
# Tuist 對 Slack 的整合 {#slack}

Tuist 對 Slack 的整合會將建置、測試和套件大小的洞察直接呈現於你的頻道中。它將監控從團隊需要記住去做的任務，轉變為自動發生的事情。例如，你的團隊可以接收每日的建置效能、快取命中率或套件大小趨勢摘要，並在關鍵指標倒退或測試變得不穩定時立即收到警報。

本頁說明此整合的功能、如何按頻道安裝，以及 Tuist 如何處理你的資料。有關 Tuist 如何收集、管理和儲存第三方資料的詳情，請參閱我們的[隱私權政策](https://tuist.dev/privacy)。

## 整合運作方式 {#how-it-works}

Tuist 透過 Slack 的[Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks)將通知傳送到 Slack。此整合僅請求`incoming-webhook`權限範圍。每個通知目的地（專案報告、警報規則、不穩定測試警報、自動化動作）對應你在安裝時選擇的一個 Slack 頻道。Slack 會為每個頻道建立一個 webhook URL，而 Tuist 會儲存該 URL 以傳送訊息。

Tuist 絕不會讀取你工作區中的訊息、成員清單或任何其他資料。此整合只會將通知寫入你明確授權的頻道。

## 設定 {#setup}

### 專案報告 {#project-reports}

專案報告會將你專案的建置、測試和快取指標每日摘要傳送到你選擇的 Slack 頻道。

1. 在 Tuist 儀表板中開啟你專案的通知設定。
2. 點擊**選擇 Slack 頻道**，並選擇你希望 Tuist 張貼訊息的工作區和頻道。Slack 會要求你授權`incoming-webhook`權限範圍並選擇單一頻道。
3. 選擇你希望每日報告送達的星期幾和時間。

![顯示包含 Slack 報告設定的通知設定圖片](/images/guides/integrations/slack/notifications-settings.png)

設定完成後，Tuist 會自動將每日報告傳送到所選頻道：

<img src="/images/guides/integrations/slack/report.png" alt="顯示 Slack 報告訊息的圖片" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> 若要張貼至私人頻道，請先在 Slack 中開啟該頻道，並在授權步驟中將其新增至整合可見的頻道清單。
> <!-- -->

### 警報規則 {#alert-rules}

當關鍵指標顯著倒退時，警報規則會在 Slack 中通知你，幫助你盡快發現建置變慢、快取效能下降或測試變慢的情況。

若要建立警報規則，請前往你專案的通知設定並點擊**新增警報規則**。你可以設定：

- **名稱**：警報的描述性名稱
- **類別**：要測量的項目（建置持續時間、測試持續時間、快取命中率或套件大小）
- **指標**：如何匯總資料（p50、p90、p99 或平均值）
- **偏差**：觸發警報的百分比變化
- **滾動視窗**：用於比較的最近執行次數
- **分支**：對於快取命中率警報，將比較限制在單一分支上的執行。留空以考慮所有分支。套件大小警報始終針對單一分支。
- **Slack 頻道**：目的地頻道。你透過上述相同的`incoming-webhook`流程授權該頻道。

例如，你可以建立一個警報，當 p90 建置持續時間相比前 100 次建置增加超過 20% 時觸發。

當只有預設分支會填充快取時，將快取命中率警報限定於該分支非常有用。觸及底層模組的 Pull Request 分支合理地錯過快取，若將它們納入會導致警報在預期內的倒退時觸發。

快取命中率警報只會比較可以公平比較的視窗。兩個視窗必須包含與滾動視窗大小相同數量的執行，且僅出現在其中一個視窗中的快取資料來源會被排除在兩者之外。因此，尚未累積足夠兩次滾動視窗大小執行次數的分支，或名稱無法匹配的分支，永遠不會觸發規則。如果你將規則限定於低流量分支，請保持滾動視窗足夠小，以便該分支能填滿它。

當警報觸發時，你將在 Slack 頻道中收到類似以下的訊息：

<img src="/images/guides/integrations/slack/alert.png" alt="顯示 Slack 警報訊息的圖片" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> 警報觸發後，同一規則在 24 小時內不會再次觸發。這可防止當指標持續偏高時產生通知疲勞。
> <!-- -->

### 不穩定測試警報 {#flaky-test-alerts}

當 Tuist 偵測到新的不穩定測試時，不穩定測試警報會立即觸發，幫助你在影響團隊之前發現測試不穩定的情況。

若要建立不穩定測試警報規則，請前往你專案的通知設定並點擊**新增不穩定測試警報規則**。你可以設定：

- **名稱**：警報的描述性名稱
- **觸發閾值**：過去 30 天內觸發警報所需的不穩定執行最小次數
- **Slack 頻道**：目的地頻道，透過`incoming-webhook`流程授權。

當測試變得不穩定並達到你的閾值時，你將收到包含直接連結以調查測試案例的通知：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="顯示 Slack 不穩定測試警報訊息的圖片" style="max-width: 500px;" />

## 中斷整合 {#disconnect}

若要停止通知，請從 Tuist 儀表板中的報告、警報規則或自動化動作移除已設定的 Slack 頻道。若要完全撤銷 Tuist 的存取權限，請在 Slack 內透過**設定與管理 → 管理應用程式**移除 webhook 整合。
