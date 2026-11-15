---
{
  "title": "Gradle 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 在團隊與 CI 之間共用 Gradle 建置快取產物。"
}
---
# Gradle 快取 {#gradle-cache}

Tuist 提供一個 Gradle 外掛程式，可與 [Gradle 內建的建置快取](https://docs.gradle.org/current/userguide/build_cache.html) 整合，以遠端分享建置產物。當任務的輸出已存在於快取中時，Gradle 會略過執行並從 Tuist 的遠端快取拉取結果，為你的團隊與 CI 環境節省建置時間。若要了解快取能消除緩慢建置中的哪些部分，以及應優先修正專案中的哪些問題，請參閱 [Slow builds](https://tuist.dev/solutions/slow-builds)。

安裝 <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle plugin</.localized_link> 後，你還需要在 `gradle.properties` 檔案中啟用 Gradle 的建置快取：

```properties
org.gradle.caching=true
```

若未設定，Gradle 不會啟動其建置快取子系統——即使已設定遠端快取——所有任務都會執行，但不會命中或填入快取。啟用後，Gradle 會將 Tuist 用作遠端建置快取，在快取命中時下載已快取的任務輸出，並在任務執行後上傳。

## 快取上傳政策 {#cache-upload-policy}

預設情況下，外掛程式會同時從遠端快取下載並上傳產物。你可以透過 `buildCache` 區塊中的 `push` 選項控制上傳行為：

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

常見的做法是僅從 CI 推送產物，因為那裡的建置具有可重複性，同時讓本機環境保持唯讀：

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

透過此設定，本機建置可以在不上傳的情況下受益于已快取的產物，而 CI 建置則會為團隊其他成員填充快取。

## 持續整合 {#continuous-integration}

在 CI 環境中，請使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中所述的方法之一進行驗證。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以取得針對不同供應商的 CI 範例。

### 停用本機建置快取 {#disabling-the-local-build-cache}

Gradle 同時維護本機與遠端建置快取。本機建置快取會將任務輸出儲存在磁碟上的 `~/.gradle/caches/build-cache-1` 目錄中。

當 Tuist 設定為遠端建置快取時，建議在 CI 上停用本機建置快取。這可避免在 CI 執行器上儲存冗餘產物，並確保建置始終以最新項目填充遠端快取，供團隊其他成員使用。

在你的 `settings.gradle.kts` 中停用 CI 上的 Gradle 本機建置快取：

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

這樣可讓本機建置快取在本機開發時保持可用，同時在 CI 上停用，由 Tuist 的遠端快取處理產物分享。

## 設定參考 {#configuration-reference}

`buildCache` 區塊支援以下選項：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 是否啟用遠端建置快取。 |
| `push` | `Boolean` | `true` | 是否將任務輸出上傳至遠端快取。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 是否允許不安全的 HTTP 連線。 |
