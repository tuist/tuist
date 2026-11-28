---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI 供應商 · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist Runners 上執行你嘅第一個 Buildkite 工作：連接你嘅叢集，用 Tuist 設定檔命名佇列，然後從步驟中定位該佇列。"
}
---
# Buildkite {#buildkite}



Tuist 會監察你 Buildkite 叢集中的自託管佇列，並喺機隊上執行搵到嘅工作。你嘅 pipeline 會繼續喺 Buildkite 上運行；只有運算資源會改變。要喺機隊上執行工作，需要三個步驟：連接你嘅叢集、將佇列命名為對應 Tuist <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>，並喺步驟中指定該佇列。

1. **連接你嘅叢集。** 喺 Buildkite 中，打開你嘅叢集，前往 **Agent Tokens** 並建立一個 token；它以 `bkct_` 開頭。喺你嘅 Tuist 儀表板中，前往 **Settings → Integrations**，喺 Buildkite 卡片上選擇 **Connect**，然後輸入你嘅組織 slug 同 token。Token 會以加密方式儲存，之後唔會再顯示。如果之後要更改組織或輪換 token，請編輯卡片上嘅欄位並選擇 **Save changes**。Tuist 會喺一分鐘內開始監察該叢集。
2. **將佇列命名為對應 Tuist 設定檔。** 每個已啟用嘅帳戶都會預設兩個即用型 <.localized_link href="/guides/features/runners/profiles">設定檔</.localized_link>：`linux` 同 `macos`。當工作嘅佇列鍵與設定檔標籤匹配時，就會被接收。喺你嘅叢集中建立鍵值為 `tuist-linux` 同 `tuist-macos` 嘅自託管佇列，然後喺步驟中指定其中一個：

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

3. **推送並監察。** 工作會被加入佇列，由 runner 領取，並將日誌串流回你 Tuist 儀表板嘅 **Runners** 部分，你可以喺嗰度追蹤其日誌、步驟同機器指標。Runner 會使用僅限於該工作嘅憑證，從工作內部傳送日誌，因此無需 Buildkite API token。

## 暫停同斷開連接 {#pausing-and-disconnecting}

暫停 Buildkite 佇列嘅調度會阻止 Tuist 從中接收新工作。已經運行中嘅工作不受影響。

喺 **Settings → Integrations** 下嘅 Buildkite 卡片上斷開叢集連接，會完全停止 Tuist 對其嘅監察。

## 快取卷 {#cache-volumes}

使用 <.localized_link href="/guides/features/runners/cache-volumes">快取卷</.localized_link> 喺不同工作之間保留 Xcode、模組同 Gradle 快取以及其他目錄。喺 checkout 之後、使用它們嘅命令之前添加它們。
