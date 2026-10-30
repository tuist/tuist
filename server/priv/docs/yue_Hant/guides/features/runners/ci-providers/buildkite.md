---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist Runners 上執行你的第一個 Buildkite 工作：連接你的叢集，以 Tuist profile 命名佇列，並從步驟中指定該佇列。"
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Runners 目前僅限邀請。請[聯絡我們](mailto:contact@tuist.dev)，或在[社區 Slack](https://slack.tuist.dev)中聯絡我們，為你的帳戶申請存取權限。

Tuist 會監察你 Buildkite 叢集中的自託管佇列，並在運算節點群組上執行找到的工作。你的流水線繼續在 Buildkite 上運行；只有運算資源改變。要在運算節點群組上執行工作，需要三個步驟：連接你的叢集、以 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>命名佇列，並從步驟中指定該佇列。

1. **申請存取權限。** 在測試階段，Runners 僅限邀請。[聯絡我們](mailto:contact@tuist.dev)並提供你想啟用的帳戶。
2. **連接你的叢集。** 在 Buildkite 中，打開你的叢集，前往**Agent Tokens**並建立一個令牌；它以`bkct_`開頭。在你的 Tuist 儀表板中，前往**Settings → Integrations**，在 Buildkite 卡片上選擇**Connect**，然後輸入你的組織 slug 和令牌。令牌會加密儲存，之後不會再顯示。如需稍後更改組織或輪換令牌，請編輯卡片上的欄位並選擇**Save changes**。Tuist 會在一分鐘內開始監察該叢集。
3. **以 Tuist 設定檔命名佇列。** 每個已啟用的帳戶都會預設兩個可用的<.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux`和`macos`。當工作的佇列鍵與設定檔的標籤匹配時，工作就會被接取。在你的叢集中建立鍵值為`tuist-linux`和`tuist-macos`的自託管佇列，然後從步驟中指定其中一個：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **推送並監控。** 工作會被加入佇列、由 runner 接取，並將串流資料傳回 Tuist 儀表板的**Runners**部分，你可以在那裡追蹤其日誌、步驟和機器指標。Runner 會使用僅限該工作的憑證，從工作內部傳送日誌，因此不需要 Buildkite API 令牌。

## 暫停與斷開連接 {#pausing-and-disconnecting}

暫停 Buildkite 佇列的分派會阻止 Tuist 從該佇列接取新工作。已經運行的工作不受影響。

在**Settings → Integrations**下的 Buildkite 卡片上斷開叢集連接，會完全停止 Tuist 對其的監察。

## 快取卷冊 {#cache-volumes}

使用<.localized_link href="/guides/features/runners/cache-volumes">快取卷冊</.localized_link>在工作之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在檢出程式碼之後、在使用它們的命令之前添加這些卷冊。
