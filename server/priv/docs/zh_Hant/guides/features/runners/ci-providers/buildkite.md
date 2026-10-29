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
> Tuist Runners 目前僅限邀請。請[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們，以申請您的帳戶存取權限。

Tuist 會監控您 Buildkite 叢集中的自託管佇列，並在執行器集群上執行其中發現的作業。您的管線仍會在 Buildkite 上執行；只有運算資源會改變。要在執行器集群上執行作業，需要進行三項變更：連接您的叢集、將佇列命名為與 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>相符的名稱，並從步驟中指向該佇列。

1. **申請存取權限。** 在測試期間，Runners 僅限邀請。[聯絡我們](mailto:contact@tuist.dev)並提供您希望啟用的帳戶。
2. **連接您的叢集。** 在 Buildkite 中，開啟您的叢集，前往**Agent Tokens**並建立一個權杖；它以`bkct_`開頭。在您的 Tuist 儀表板中，前往**Settings → Integrations**，在 Buildkite 卡片上選擇**Connect**，然後輸入您的組織簡稱和權杖。該權杖會以加密方式儲存，且不會再次顯示。若日後要變更組織或輪換權杖，請編輯卡片上的欄位並選擇**Save changes**。Tuist 會在一分鐘內開始監控該叢集。
3. **將佇列命名為與 Tuist 設定檔相符。** 每個已啟用的帳戶一開始就有兩個可直接使用的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux`和`macos`。當作業的佇列鍵值與設定檔的標籤相符時，就會被選取執行。在您的叢集中建立鍵值為`tuist-linux`和`tuist-macos`的自託管佇列，然後從步驟中指向其中一個：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **推送並監控。** 作業會被加入佇列、由執行器領取，並將串流資料回傳至您 Tuist 儀表板的**Runners**區段，您可以在那裡追蹤其日誌、步驟和機器指標。執行器會使用僅限該作業範圍的憑證，從作業內部傳送日誌，因此不需要 Buildkite API 權杖。

## 暫停與斷開連線 {#pausing-and-disconnecting}

暫停 Buildkite 佇列的分派功能會阻止 Tuist 從中接收新作業。已在執行的作業不受影響。

在**Settings → Integrations**下的 Buildkite 卡片上斷開叢集連線，會讓 Tuist 完全停止監控該叢集。

## 快取磁碟區 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link>在作業之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在 checkout 之後以及在使用這些目錄的命令之前新增它們。
