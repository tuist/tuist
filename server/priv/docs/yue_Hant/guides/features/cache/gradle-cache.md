---
{
  "title": "Gradle 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 與團隊及 CI 共用 Gradle 建置快取項目。"
}
---
# Gradle 快取 {#gradle-cache}

Tuist 提供一個 Gradle 外掛程式，可與 [Gradle 內建的組建快取](https://docs.gradle.org/current/userguide/build_cache.html) 整合，以遠端共用組建成品。當某個工作（task）的輸出已存在於快取中時，Gradle 會略過執行，並從 Tuist 的遠端快取拉取結果，為你的團隊及 CI 環境節省組建時間。

安裝 <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 外掛程式</.localized_link> 後，你還需要在 `gradle.properties` 檔案中啟用 Gradle 的組建快取：

```properties
org.gradle.caching=true
```

若未進行此設定，即使已設定遠端快取，Gradle 也不會啟動其組建快取子系統，所有工作都會在無法命中或寫入快取的情況下執行。啟用後，Gradle 會將 Tuist 用作遠端組建快取，在快取命中時下載已快取的工作輸出，並在工作執行後上傳它們。

## 快取上傳政策 {#cache-upload-policy}

預設情況下，外掛程式會同時從遠端快取下載及上傳成品。你可以透過 `buildCache` 區塊中的 `push` 選項來控制上傳行為：

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

常見的做法是只在 CI 環境推送成品，因為那裡的組建是可重現的，同時讓本機環境保持唯讀：

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

在此設定下，本機組建可以受益於已快取的成品而無需上傳，而 CI 組建則會為團隊其他成員填充快取。

## 持續整合 {#continuous-integration}

對於 CI 環境，請使用 <.localized_link href="/guides/server/authentication#continuous-integration">驗證指南</.localized_link> 中其中一種方法進行驗證。如需特定供應商的 CI 範例，請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link>。

### 停用本機組建快取 {#disabling-the-local-build-cache}

Gradle 同時維護本機和遠端組建快取。本機組建快取會將工作輸出儲存在磁碟上的 `~/.gradle/caches/build-cache-1` 目錄中。

當 Tuist 被設定為遠端組建快取時，建議在 CI 上停用本機組建快取。這可以避免在 CI 執行器上儲存冗餘成品，並確保組建始終為團隊其他成員在遠端快取中填充新的條目。

在你的 `settings.gradle.kts` 中停用 CI 上的 Gradle 本機組建快取：

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

這樣可以讓本機組建快取在本機開發時保持可用，同時在 CI 上停用它，由 Tuist 的遠端快取處理成品共用。

## 設定參考 {#configuration-reference}

`buildCache` 區塊支援以下選項：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 是否啟用遠端組建快取。 |
| `push` | `Boolean` | `true` | 是否將工作輸出上傳至遠端快取。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 是否允許不安全的 HTTP 連線。 |
