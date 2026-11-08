---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "喺 Tuist Runners 執行你嘅第一個 Buildkite 工作：連接你嘅叢集，用 Tuist profile 命名佇列，然後從步驟中指向它。"
}
---
# Buildkite {#buildkite}

<!-- @snippet: ./_invite-only -->

Tuist 會監察你 Buildkite 叢集中的自託管佇列，並在機隊上執行找到的工作。你的 pipeline 會繼續在 Buildkite 上運行；只有運算資源有所改變。要在機隊上執行工作，需要進行三項變更：連接你的叢集、以 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link> 命名佇列，並從步驟中指定該佇列。

1. **連接你的叢集。** 在 Buildkite 中，開啟你的叢集，前往 **Agent Tokens** 並建立一個 token；它以 `bkct_` 開頭。在你的 Tuist 儀表板中，前往 **Settings → Integrations**，在 Buildkite 卡片上選擇 **Connect**，然後輸入你的組織 slug 和 token。Token 會以加密方式儲存，之後不會再顯示。如要稍後更改組織或輪換 token，請編輯卡片上的欄位並選擇 **Save changes**。Tuist 會在一分鐘內開始監察該叢集。
2. **以 Tuist 設定檔命名佇列。** 每個已啟用的帳戶都預設提供兩個可用的 <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 和 `macos`。當工作的佇列鍵與設定檔的標籤匹配時，工作就會被接收。在你的叢集中建立鍵值為 `tuist-linux` 和 `tuist-macos` 的自託管佇列，然後從步驟中指定其中一個：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

3. **推送並監控。** 工作會被放入佇列，由 runner 領取，並串流回 Tuist 儀表板的 **Runners** 部分，你可以在那裡追蹤其日誌、步驟和機器指標。Runner 會使用僅限於該工作的憑證，從工作內部傳送日誌，因此不需要 Buildkite API token。

## 暫停與斷開連接 {#pausing-and-disconnecting}

暫停 Buildkite 佇列的分派會阻止 Tuist 從中接收新工作。已經運行的工作不受影響。

在 **Settings → Integrations** 下的 Buildkite 卡片上斷開叢集連接，會完全停止 Tuist 對其的監察。

## 快取卷宗 {#cache-volumes}

使用 <.localized_link href="/guides/features/runners/cache-volumes">快取卷宗</.localized_link> 在工作之間保留 Xcode、模組和 Gradle 快取以及其他目錄。在 checkout 之後以及在使用它們的命令之前添加它們。
