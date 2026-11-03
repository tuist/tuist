---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI 供應商 · 執行器 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 執行器上執行你的第一個 Buildkite 工作：連接你的叢集，以 Tuist 設定檔命名佇列，並從步驟中指定該佇列。"
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前採邀請制。[聯絡我們](mailto:contact@tuist.dev)或在 [社群 Slack](https://slack.tuist.dev) 中聯繫我們，為你的帳戶申請存取權限。

Tuist 會監控你 Buildkite 叢集中的自管佇列，並在執行器群集上執行找到的工作。你的流水線仍會在 Buildkite 上執行；只有運算資源改變。要在群集上執行工作，需要進行三項變更：連接你的叢集、以 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link> 命名佇列，並從步驟中指定該佇列。

1. **申請存取權限。** 測試期間，Runners 採邀請制。[聯絡我們](mailto:contact@tuist.dev)並提供你想要啟用的帳戶。
2. **連接你的叢集。** 在 Buildkite 中，開啟你的叢集，前往 **Agent Tokens** 並建立權杖；其開頭為 `bkct_`。在你的 Tuist 儀表板中，前往 **Settings → Integrations**，在 Buildkite 卡片上選擇 **Connect**，然後輸入你的組織 slug 和權杖。權杖會以加密方式儲存，且不會再次顯示。若之後要變更組織或輪換權杖，請編輯卡片上的欄位並選擇 **Save changes**。Tuist 會在一分鐘內開始監控該叢集。
3. **以 Tuist 設定檔命名佇列。** 每個已啟用的帳戶都會預設兩個可直接使用的 <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 與 `macos`。當工作的佇列金鑰與設定檔的標籤相符時，就會被選取執行。在你的叢集中建立金鑰為 `tuist-linux` 和 `tuist-macos` 的自管佇列，然後從步驟中指定其中一個：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **推送並監控。** 工作會被放入佇列、由執行器領取，並將串流資料回傳至 Tuist 儀表板的 **Runners** 區段，你可以在這裡追蹤其日誌、步驟與機器指標。執行器會使用範圍限定於該單一工作的憑證，從工作內部傳送日誌，因此不需要 Buildkite API 權杖。

## 暫停與中斷連線 {#pausing-and-disconnecting}

暫停 Buildkite 佇列的分派作業，可阻止 Tuist 從該佇列取得新工作。已在執行的工作不受影響。

在 **Settings → Integrations** 下的 Buildkite 卡片上中斷叢集連線，會讓 Tuist 完全停止監控該叢集。

## 快取磁碟區 {#cache-volumes}

使用 <.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link> 在工作之間保留 Xcode、模組與 Gradle 快取以及其他目錄。在检出程式碼之後、使用這些目錄的命令之前加入它們。
