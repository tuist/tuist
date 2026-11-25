---
{
  "title": "Gradle 建置快取：為 CI 與團隊設定遠端快取",
  "titleTemplate": ":title · Tuist",
  "description": "使用 Tuist 外掛程式與 org.gradle.caching=true 設定 Gradle 遠端建置快取，讓 CI 與開發人員重複使用任務輸出，而非重新執行任務。"
}
---
# Gradle 建置快取 {#gradle-cache}

Tuist 是 Gradle 遠端建置快取：其 Gradle 外掛程式將 [Gradle 內建的建置快取](https://docs.gradle.org/current/userguide/build_cache.html) 連線至共用伺服器，讓 CI 與每台開發機器都能重複使用任務輸出，而非重新執行任務。當任務的輸出已存在快取中時，Gradle 會略過執行並從 Tuist 取得結果，為你的團隊與 CI 環境節省建置時間。若想了解 Tuist 還為 Gradle 建置帶來哪些功能（例如建置洞察與測試洞察），請參閱 [搭配 Tuist 使用 Gradle](https://tuist.dev/build-systems/gradle)；若要與 Develocity 比較，請參閱 [Develocity 與 Tuist](https://tuist.dev/compare/develocity)。若想瞭解 Gradle 的本機與遠端建置快取與最新狀態檢查及設定快取的差異，請參閱 <.localized_link href="/references/concepts/build-cache#gradle">什麼是建置快取？</.localized_link>。若要找出快取能移除緩慢建置中的哪一部分，以及應優先修正專案中的哪些問題，請參閱 [緩慢建置](https://tuist.dev/solutions/slow-builds)。

安裝 <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle 外掛程式</.localized_link> 後，你還需要在 `gradle.properties` 檔案中啟用 Gradle 的建置快取：

```properties
org.gradle.caching=true
```

若未進行此設定，Gradle 不會啟用其建置快取子系統——即使已設定遠端快取——所有任務都會在無法命中或寫入快取的情況下執行。啟用後，Gradle 會將 Tuist 作為遠端建置快取使用，在快取命中時下載已快取的任務輸出，並在任務執行後上傳它們。

## 快取上傳政策 {#cache-upload-policy}

預設情況下，外掛程式會同時從遠端快取下載並上傳構件。你可以透過 `buildCache` 區塊中的 `push` 選項來控制上傳行為：

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

常見的做法是僅從 CI 推送構件（因為 CI 中的建置具有可重現性），同時將本機環境設為唯讀：

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

在此設定下，本機建置能在不上傳的情況下受益于已快取的構件，而 CI 建置則會為團隊其他成員填充快取。

## 持續整合 {#continuous-integration}

在 CI 環境中，請使用 <.localized_link href="/guides/server/authentication#continuous-integration">驗證指南</.localized_link> 中的其中一種方法進行驗證。請參閱 <.localized_link href="/guides/integrations/continuous-integration">持續整合指南</.localized_link>，查看針對不同供應商的 CI 範例。

### 停用本機建置快取 {#disabling-the-local-build-cache}

Gradle 同時維護本機與遠端建置快取。本機建置快取會將任務輸出儲存在磁碟上的 `~/.gradle/caches/build-cache-1` 目錄中。

當 Tuist 設定為遠端建置快取時，建議在 CI 上停用本機建置快取。這可避免在 CI 執行器上儲存冗餘構件，並確保建置始終為團隊其他成員在遠端快取中填入新的項目。

在你的 `settings.gradle.kts` 中停用 CI 上的 Gradle 本機建置快取：

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

這樣可在本機開發時保留本機建置快取，同時在 CI 上將其停用，由 Tuist 的遠端快取負責處理構件共享。

## 設定參考 {#configuration-reference}

`buildCache` 區塊支援以下選項：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 是否啟用遠端建置快取。 |
| `push` | `Boolean` | `true` | 是否將任務輸出上傳至遠端快取。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 是否允許不安全的 HTTP 連線。 |
