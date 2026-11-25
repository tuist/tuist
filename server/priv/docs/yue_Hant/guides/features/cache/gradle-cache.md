---
{
  "title": "Gradle 建構快取：為 CI 同團隊設定遠端快取",
  "titleTemplate": ":title · Tuist",
  "description": "使用 Tuist 外掛程式同 org.gradle.caching=true 設定 Gradle 遠端建構快取，讓 CI 同開發人員重用任務輸出，而唔係重新執行任務。"
}
---
# Gradle 建構快取 {#gradle-cache}

Tuist 係 Gradle 遙端建構快取：佢嘅 Gradle 外掛程式將 [Gradle 內置嘅建構快取](https://docs.gradle.org/current/userguide/build_cache.html) 連接到共用伺服器，令 CI 同每台開發者機器都可以重用任務輸出，而唔使重新執行任務。當任務輸出已經被快取時，Gradle 會跳過執行並從 Tuist 拉取結果，為你嘅團隊同 CI 環境節省建構時間。如想了解 Tuist 為 Gradle 建構帶來嘅其他功能（例如建構洞察同測試洞察），請參閱 [Gradle with Tuist](https://tuist.dev/build-systems/gradle)；如果你正將其與 Develocity 比較，請參閱 [Develocity vs Tuist](https://tuist.dev/compare/develocity)。如想了解 Gradle 本地同遙端建構快取與最新狀態檢查及配置快取有何不同，請參閱 <.localized_link href="/references/concepts/build-cache#gradle">What is a build cache?</.localized_link>。如想找出快取消除咗慢速建構中嘅哪一部分，以及應該優先修復項目中嘅什麼問題，請參閱 [Slow builds](https://tuist.dev/solutions/slow-builds)。

安裝 <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle plugin</.localized_link> 之後，你亦需要喺你嘅 `gradle.properties` 檔案中啟用 Gradle 嘅建構快取：

```properties
org.gradle.caching=true
```

如果冇呢個設定，Gradle 唔會啟動其建構快取子系統——即使已配置遙端快取——所有任務都會執行，而唔會命中或填充快取。一旦啟用，Gradle 就會使用 Tuist 作為遙端建構快取，喺快取命中時下載已快取嘅任務輸出，並喺任務執行後上傳佢哋。

## 快取上傳政策 {#cache-upload-policy}

預設情況下，外掛程式會同時從遙端快取下載同上傳構件。你可以透過 `buildCache` 區塊中嘅 `push` 選項嚟控制上傳：

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

一個常見嘅模式係只從 CI 推送構件，因為那裡嘅建構係可重現嘅，同時保持本地環境為唯讀：

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

透過呢個設定，本地建構可以受益於已快取嘅構件而無需上傳，而 CI 建構則會為團隊其他成員填充快取。

## 持續整合 {#continuous-integration}

對於 CI 環境，請使用 <.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</.localized_link> 中嘅其中一種方法進行身份驗證。請參閱 <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> 以獲取針對特定供應商嘅 CI 示例。

### 停用本地建構快取 {#disabling-the-local-build-cache}

Gradle 同時維護本地同遙端建構快取。本地建構快取將任務輸出存儲喺磁盤上嘅 `~/.gradle/caches/build-cache-1` 目錄下。

當 Tuist 被配置為遙端建構快取時，建議喺 CI 上停用本地建構快取。這可以避免喺 CI 運行器上存儲冗餘構件，並確保建構始終用新條目填充遙端快取，供團隊其他成員使用。

喺你嘅 `settings.gradle.kts` 中停用 CI 上嘅 Gradle 本地建構快取：

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

這樣做可以保持本地建構快取可用於本地開發，同時喺 CI 上停用佢，由 Tuist 嘅遙端快取處理構件共享。

## 配置參考 {#configuration-reference}

`buildCache` 區塊支持：

| 選項 | 類型 | 預設值 | 描述 |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | 是否啟用遙端建構快取。 |
| `push` | `Boolean` | `true` | 是否將任務輸出上傳到遙端快取。 |
| `allowInsecureProtocol` | `Boolean` | `false` | 是否允許不安全嘅 HTTP 連接。 |
