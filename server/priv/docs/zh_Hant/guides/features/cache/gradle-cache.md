---
{
  "title": "Gradle cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Gradle build cache artifacts across your team and CI with Tuist."
}
---
# Gradle 快取 {#gradle-cache}

Tuist 提供一個 Gradle 外掛程式，可與 [Gradle 內建的組建快取](https://docs.gradle.org/current/userguide/build_cache.html) 整合，以遠端分享組建成品。當任務的輸出已存在於快取中時，Gradle 會略過執行並從 Tuist 的遠端快取中提取結果，為您的團隊和 CI 環境節省組建時間。

安裝 <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 外掛程式</.localized_link> 後，您還需要在 `gradle.properties` 檔案中啟用 Gradle 的組建快取：

```properties
org.gradle.caching=true
```

若未進行此設定，即使已設定遠端快取，Gradle 也不會啟動其組建快取子系統，所有任務都將執行而不會命中或填充快取。啟用後，Gradle 會將 Tuist 用作遠端組建快取，在快取命中時下載已快取的任務輸出，並在任務執行後上傳它們。

## 快取上傳政策 {#cache-upload-policy}

預設情況下，外掛程式會同時下載和上傳成品至遠端快取。您可以透過 `buildCache` 區塊中的 `push` 選項來控制上傳：

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

常見的做法是僅從 CI 推送成品（因為那裡的組建是可重現的），同時保持本機環境為唯讀：

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

透過此設定，本機組建可以受益於已快取的成品而無需上傳，而 CI 組建則會為團隊其他成員填充快取。

## 持續整合 {#continuous-integration}

對於 CI 環境，請使用 <.localized_link href="/guides/server/authentication#continuous-integration">驗證指南</.localized_link> 中的一種方法進行驗證。請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以取得特定供應商的 CI 範例。

### 停用本機組建快取 {#disabling-the-local-build-cache}

Gradle 同時維護本機和遠端組建快取。本機組建快取將任務輸出儲存在磁碟上的 `~/.gradle/caches/build-cache-1` 目錄下。

當 Tuist 設定為遠端組建快取時，建議在 CI 上停用本機組建快取。這可以避免在 CI 執行器上儲存冗餘成品，並確保組建始終為團隊其他成員以新條目填充遠端快取。

在您的 `settings.gradle.kts` 中停用 CI 上的 Gradle 本機組建快取：

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

這讓本機組建快取可用於本機開發，同時在 CI 上停用它，由 Tuist 的遠端快取處理成品分享。

## 設定參考 {#configuration-reference}

`buildCache` 區塊支援：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 是否啟用遠端組建快取。 |
| `push` | `Boolean` | `true` | 是否將任務輸出上傳至遠端快取。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 是否允許不安全的 HTTP 連線。 |
