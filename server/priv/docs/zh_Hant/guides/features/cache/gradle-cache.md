---
{
  "title": "Gradle 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 在團隊與 CI 之間共用 Gradle 建置快取產物。"
}
---
# Gradle 快取 {#gradle-cache}

Tuist 提供一個 Gradle 外掛，可與 [Gradle 內建的建置快取](https://docs.gradle.org/current/userguide/build_cache.html) 整合，以遠端共用建置產物。當工作的輸出已存在於快取中時，Gradle 會略過執行並從 Tuist 的遠端快取取得結果，為你的團隊與 CI 環境節省建置時間。若要了解 Gradle 的本機與遠端建置快取如何不同於最新狀態檢查與設定快取，請參閱 <.localized_link href="/references/concepts/build-cache#gradle">什麼是建置快取？</.localized_link>。若要找出快取能消除緩慢建置中的哪些部分，以及應優先修正專案中的哪些項目，請參閱 [緩慢建置](https://tuist.dev/solutions/slow-builds)。

安裝 <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 外掛</.localized_link> 後，你還需要在 `gradle.properties` 檔案中啟用 Gradle 的建置快取：

```properties
org.gradle.caching=true
```

若未進行此設定，Gradle 不會啟用其建置快取子系統——即使已設定遠端快取——所有工作都會執行，但不會命中或填入快取。啟用後，Gradle 會將 Tuist 作為遠端建置快取使用，在快取命中時下載已快取的工作輸出，並在工作執行後上傳。

## 快取上傳政策 {#cache-upload-policy}

預設情況下，外掛會同時下載與上傳產物至遠端快取。你可以透過 `buildCache` 區塊中的 `push` 選項控制上傳行為：

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

常見的做法是僅從 CI 推送產物，因為 CI 的建置具有可重現性，同時將本機環境設為唯讀：

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

在此設定下，本機建置可受益于快取產物而無需上傳，而 CI 建置則會為團隊其他成員填入快取。

## 持續整合 {#continuous-integration}

在 CI 環境中，請使用 <.localized_link href="/guides/server/authentication#continuous-integration">驗證指南</.localized_link> 中的其中一種方法進行驗證。請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link> 以取得各供應商特定的 CI 範例。

### 停用本機建置快取 {#disabling-the-local-build-cache}

Gradle 同時維護本機與遠端建置快取。本機建置快取會將工作輸出儲存在磁碟上的 `~/.gradle/caches/build-cache-1` 目錄中。

當 Tuist 設定為遠端建置快取時，建議在 CI 上停用本機建置快取。這可避免在 CI 執行器上儲存重複的產物，並確保建置始終以新的項目填入遠端快取，供團隊其他成員使用。

在你的 `settings.gradle.kts` 中停用 CI 上的 Gradle 本機建置快取：

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

這會讓本機建置快取在本機開發時保持可用，同時在 CI 上停用，由 Tuist 的遠端快取負責產物共用。

## 設定參考 {#configuration-reference}

`buildCache` 區塊支援以下選項：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 是否啟用遠端建置快取。 |
| `push` | `Boolean` | `true` | 是否將工作輸出上傳至遠端快取。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 是否允許不安全的 HTTP 連線。 |
