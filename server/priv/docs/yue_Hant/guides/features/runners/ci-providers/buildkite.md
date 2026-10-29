---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first Buildkite job on Tuist Runners: connect your cluster, name a queue after a Tuist profile, and target it from a step."
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請。請[聯絡我們](mailto:contact@tuist.dev)或在[社區 Slack](https://slack.tuist.dev)中聯絡我們，以請求開啟你的帳戶權限。

Tuist 會監控你 Buildkite 叢集中的自託管佇列，並在運算資源池中執行找到的工作。你的管道仍會在 Buildkite 上運行；只有運算資源會改變。要在運算資源池上執行工作，需要進行三項變更：連接你的叢集、將佇列命名為對應 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>的名稱，並從步驟中指定該佇列。

1. **請求存取權限。** 在測試期間，Runners 僅限邀請使用。請[聯絡我們](mailto:contact@tuist.dev)並提供你想要啟用的帳戶。
2. **連接你的叢集。** 在 Buildkite 中，打開你的叢集，前往**Agent Tokens**並建立一個 token；它以`bkct_`開頭。在你的 Tuist 儀表板中，前往**Settings → Integrations**，在 Buildkite 卡片上選擇**Connect**，然後輸入你的組織 slug 和 token。該 token 會以加密方式儲存，且不會再次顯示。日後若要更改組織或輪換 token，請編輯卡片上的欄位並選擇**Save changes**。Tuist 會在一分鐘內開始監控該叢集。
3. **將佇列命名為對應 Tuist 設定檔的名稱。** 每個已啟用的帳戶都會預設兩個可直接使用的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux`和`macos`。當工作的佇列金鑰與設定檔的標籤相符時，就會被選取執行。在你的叢集中建立金鑰為`tuist-linux`和`tuist-macos`的自託管佇列，然後從步驟中指定其中一個：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **推送並監控。** 工作會被加入佇列、由 runner 領取，並串流回 Tuist 儀表板的**Runners**部分，你可以在那裡追蹤其日誌、步驟和機器指標。Runner 會使用僅限該工作範圍的憑證，從工作內部傳送日誌，因此不需要 Buildkite API token。

## 暫停與斷開連接 {#pausing-and-disconnecting}

暫停 Buildkite 佇列的分派會阻止 Tuist 從中接收新工作。已經運行的工作不受影響。

在**Settings → Integrations**下的 Buildkite 卡片上斷開叢集連接，會完全停止 Tuist 對其的監控。

## 快取磁碟區 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link>在工作之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在 checkout 之後以及在使用它們的命令之前添加它們。
