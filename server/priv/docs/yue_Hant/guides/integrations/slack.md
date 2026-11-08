---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "了解如何使用 Tuist 的 Slack 整合功能。"
}
---
# Tuist 的 Slack 整合 {#slack}

Tuist 的 Slack 整合會將建構、測試與套件大小的洞察直接呈現於你的頻道中。它讓監控從團隊需要記得去做的事，變成自動發生的事。例如，你的團隊可以收到每日的建構效能、快取命中率或套件大小趨勢摘要，並在關鍵指標倒退或測試變得不穩定時立即收到警示。

本頁說明此整合的功能、如何按頻道安裝，以及 Tuist 如何處理你的資料。如需了解 Tuist 如何收集、管理與儲存第三方資料的詳情，請參閱我們的[私隱政策](https://tuist.dev/privacy)。

## 整合運作方式 {#how-it-works}

Tuist 透過 Slack 的[Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks)向 Slack 發送通知。此整合只會請求`incoming-webhook`權限範圍。每個通知目的地（專案報告、警示規則、不穩定測試警示、自動化動作）都對應你在安裝時選擇的一個 Slack 頻道。Slack 會為每個頻道建立一個 webhook URL，而 Tuist 會儲存該 URL 以傳送訊息。

Tuist 絕不會讀取你工作區中的訊息、成員清單或其他任何資料。此整合只會將通知寫入你已明確授權的頻道。

## 設定 {#setup}

### 專案報告 {#project-reports}

專案報告會將你專案的建構、測試與快取指標的每日摘要，傳送至你選擇的 Slack 頻道。

1. 在 Tuist 儀表板中開啟你專案的通知設定。
2. 點擊**選取 Slack 頻道**，並選擇你希望 Tuist 發佈訊息的工作區與頻道。Slack 會要求你授權`incoming-webhook`權限範圍，並選取單一頻道。
3. 選擇你希望每日報告送達的星期幾與時間。

![顯示包含 Slack 報告設定的通知設定畫面](/images/guides/integrations/slack/notifications-settings.png)

設定完成後，Tuist 會向所選頻道自動發送每日報告：

<img src="/images/guides/integrations/slack/report.png" alt="顯示 Slack 報告訊息的圖片" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> 若要發佈至私人頻道，請先在 Slack 中開啟該頻道，並在授權步驟中將其加入整合可見的頻道清單。
> <!-- -->

### 警示規則 {#alert-rules}

當關鍵指標明顯倒退時，警示規則會在 Slack 中通知你，幫助你盡快發現建構變慢、快取退化或測試 slowdown 的情況。

要建立警示規則，請前往你專案的通知設定並點擊**新增警示規則**。你可以設定：

- **名稱**：警示的描述性名稱
- **類別**：要測量的項目（建構耗時、測試耗時、快取命中率或套件大小）
- **指標**：如何匯總資料（p50、p90、p99 或平均值）
- **偏差**：觸發警示的百分比變化
- **滾動視窗**：要用來比較的近期執行次數
- **分支**：針對快取命中率警示，將比較限制在單一分支的執行。留空則考慮所有分支。套件大小警示一律針對單一分支。
- **Slack 頻道**：目的地頻道。你可透過上述相同的`incoming-webhook`流程授權該頻道。

例如，你可以建立一個警示，當 p90 建構耗時相比前 100 次建構增加超過 20% 時觸發。

將快取命中率警示限定於你的預設分支很有用，因為只有該分支會填充快取。触及底層模組的拉取請求分支 legitimately 錯過快取是合理的，若將它們納入會導致警示在預期內的倒退時觸發。

快取命中率警示只會公平地比較可比較的視窗。兩個視窗都必須包含等於滾動視窗大小的執行次數，而只出現在其中一個視窗的快取資料來源會被排除。尚未累積足夠兩次滾動視窗大小執行次數的分支，或名稱無法匹配的分支，因此永遠不會觸發規則。若你將規則限定於低流量分支，請將滾動視窗設得夠小，讓該分支能填滿它。

當警示觸發時，你會在 Slack 頻道中收到類似以下的訊息：

<img src="/images/guides/integrations/slack/alert.png" alt="顯示 Slack 警示訊息的圖片" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> 警示觸發後，同一規則在 24 小時內不會再次觸發。這可避免在指標持續偏高時造成通知疲勞。
> <!-- -->

### 不穩定測試警示 {#flaky-test-alerts}

當 Tuist 偵測到新的不穩定測試時，不穩定測試警示會立即觸發，幫助你在影響團隊之前發現測試不穩定的情況。

要建立不穩定測試警示規則，請前往你專案的通知設定並點擊**新增不穩定測試警示規則**。你可以設定：

- **名稱**：警示的描述性名稱
- **觸發閾值**：過去 30 天內觸發警示所需的不穩定執行最少次數
- **Slack 頻道**：目的地頻道，透過`incoming-webhook`流程授權。

當測試變得不穩定並達到你的閾值時，你會收到一則包含直接連結的通知，以便調查該測試案例：

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="顯示 Slack 不穩定測試警示訊息的圖片" style="max-width: 500px;" />

## 停用整合 {#disconnect}

要停止通知，請在 Tuist 儀表板中從報告、警示規則或自動化動作移除已設定的 Slack 頻道。要完全撤銷 Tuist 的存取權限，請在 Slack 內透過**設定與管理 → 管理應用程式**移除 webhook 整合。
