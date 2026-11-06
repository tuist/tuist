---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist Runners 執行你嘅第一個 Buildkite 工作：連接你嘅叢集、用 Tuist 設定檔命名佇列，然後從步驟中指向佢。"
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請。[聯絡我們](mailto:contact@tuist.dev)或於[社區 Slack](https://slack.tuist.dev)留言，以申請你帳戶的存取權限。

Tuist 會監察你 Buildkite 叢集中的自託管佇列，並在運算資源池上執行找到的工作。你的流水線仍會在 Buildkite 上運行；只有運算資源有所改變。要在運算資源池上執行工作，需要進行三項變更：連接你的叢集、將佇列命名為對應 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>的名稱，並從步驟中指定該佇列。

1. **申請存取權限。** 在測試期間，Runners 僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)並提供你想要啟用的帳戶。
2. **連接你的叢集。** 在 Buildkite 中，開啟你的叢集，前往**Agent Tokens**並建立一個令牌；它以`bkct_`開頭。在你的 Tuist 儀表板中，前往**Settings → Integrations**，在 Buildkite 卡片上選擇**Connect**，然後輸入你的組織 slug 和令牌。令牌會以加密方式儲存，之後不會再顯示。如要日後更改組織或輪換令牌，請編輯卡片上的欄位並選擇**Save changes**。Tuist 會在一分鐘內開始監察該叢集。
3. **將佇列命名為對應 Tuist 設定檔的名稱。** 每個已啟用的帳戶都會預設兩個可直接使用的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux`和`macos`。當工作的佇列鍵與某個設定檔的標籤相符時，該工作就會被接取。在你的叢集中建立鍵值為`tuist-linux`和`tuist-macos`的自託管佇列，然後從步驟中指定其中一個：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **推送並監控。** 工作會被加入佇列、由 runner 領取，並將串流資料回傳至 Tuist 儀表板的**Runners**部分，你可以在此追蹤其日誌、步驟及機器指標。Runner 會使用僅限該工作的憑證，從工作內部傳送日誌，因此不需要 Buildkite API 令牌。

## 暫停與斷開連接 {#pausing-and-disconnecting}

暫停 Buildkite 佇列的分派功能，會阻止 Tuist 從該佇列接收新工作。已經執行的工作不會受到影響。

在**Settings → Integrations**下的 Buildkite 卡片中斷開叢集連接，會完全停止 Tuist 對其的監察。

## 快取磁碟區 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取磁碟區</.localized_link>在不同工作之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在检出程式碼之後、執行使用這些目錄的命令之前加入它們。
