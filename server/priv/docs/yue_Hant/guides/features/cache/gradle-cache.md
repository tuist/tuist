---
{
  "title": "Gradle 快取",
  "titleTemplate": ":title · Cache · 功能 · Guides · Tuist",
  "description": "透過 Tuist 喺團隊同 CI 之間共享 Gradle 建構快取構件。"
}
---
# Gradle 快取 {#gradle-cache}

Tuist 提供一個 Gradle 外掛程式，可與 [Gradle 內建的建構快取](https://docs.gradle.org/current/userguide/build_cache.html) 整合，以遠端共用建構產物。當任務的輸出已存在快取中時，Gradle 會跳過執行並從 Tuist 的遠端快取提取結果，為你的團隊和 CI 環境節省建構時間。如需了解 Gradle 的本機和遠端建構快取與最新狀態檢查及設定快取有何不同，請參閱 <.localized_link href="/references/concepts/build-cache#gradle">什麼是建構快取？</.localized_link>。若要找出快取能消除緩慢建構中的哪一部分，以及應優先修復專案中的哪些問題，請參閱 [緩慢的建構](https://tuist.dev/solutions/slow-builds)。

安裝 <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 外掛程式</.localized_link> 後，你還需要在 `gradle.properties` 檔案中啟用 Gradle 的建構快取：

```properties
org.gradle.caching=true
```

如果沒有此設定，Gradle 不會啟動其建構快取子系統——即使已設定遠端快取——所有任務都會執行，但不會命中或填充快取。啟用後，Gradle 會將 Tuist 用作遠端建構快取，在命中快取時下載已快取的任務輸出，並在任務執行後上傳它們。

## 快取上傳政策 {#cache-upload-policy}

預設情況下，外掛程式會同時下載和上傳產物到遠端快取。你可以使用 `buildCache` 區塊中的 `push` 選項來控制上傳：

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

常見的做法是僅從 CI 推送產物（因為那裡的建構是可重現的），同時保持本機環境為唯讀：

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

透過此設定，本機建構可以受益於已快取的產物而無需上傳，而 CI 建構則會為團隊其他成員填充快取。

## 持續整合 {#continuous-integration}

對於 CI 環境，請使用 <.localized_link href="/guides/server/authentication#continuous-integration">驗證指南</.localized_link> 中的其中一種方法進行驗證。請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以獲取特定供應商的 CI 範例。

### 停用本機建構快取 {#disabling-the-local-build-cache}

Gradle 同時維護本機和遠端建構快取。本機建構快取將任務輸出儲存在磁碟上的 `~/.gradle/caches/build-cache-1` 目錄下。

當 Tuist 設定為遠端建構快取時，建議在 CI 上停用本機建構快取。這可以避免在 CI 執行器上儲存冗餘產物，並確保建構始終用新條目填充遠端快取，供團隊其他成員使用。

在你的 `settings.gradle.kts` 中停用 CI 上的 Gradle 本機建構快取：

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

這樣可以讓本機建構快取在本機開發時可用，同時在 CI 上停用它，由 Tuist 的遠端快取處理產物共用。

## 設定參考 {#configuration-reference}

`buildCache` 區塊支援以下選項：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 是否啟用遠端建構快取。 |
| `push` | `Boolean` | `true` | 是否將任務輸出上傳到遠端快取。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 是否允許不安全的 HTTP 連線。 |
