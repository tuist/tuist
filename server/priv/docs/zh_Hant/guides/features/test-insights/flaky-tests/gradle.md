---
{
  "title": "Gradle 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 在 Gradle 專案中偵測、管理及隔離不穩定測試。"
}
---
# Gradle 不穩定測試 {#gradle-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 已設定 <.localized_link href="/guides/features/test-insights/gradle">Gradle 測試洞察</.localized_link>。

<!-- @snippet: ./_intro -->

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測的運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你執行具備重試功能的測試時，Tuist 會分析每次嘗試的結果。如果某個測試在某些嘗試中失敗、在其他嘗試中通過，就會被標記為不穩定。

你可以使用 [Test Retry 外掛程式](https://github.com/gradle/test-retry-gradle-plugin) 或類似機制來重新執行失敗的測試。Tuist 會偵測到那些在某些嘗試中通過、在其他嘗試中失敗的測試。

將外掛程式加入你的 `build.gradle.kts`：

```kotlin
plugins {
    id("org.gradle.test-retry") version "1.6.2"
}

tasks.test {
    retry {
        maxRetries = 3
        maxFailures = 5
        failOnPassedAfterRetry = false
    }
}
```

![不穩定測試案例詳細資訊](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也能透過比較同一個提交與同一個 Gradle 專案在不同 CI 執行中的結果，來偵測不穩定測試。如果某個測試在一次 CI 執行中通過，但在同一個提交與專案的另一次執行中失敗，該失敗的執行就會被標記為不穩定。

Gradle 專案是比較鍵的一部分，因為同一個測試在不同專案中可能會有確定性的不同行為——例如，一個共用的測試類別以不同的相依性編譯，或在不同的模組固定裝置上執行。同一個提交在不同 Gradle 專案上的兩次執行會被視為獨立的執行變體，不會互相標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試抓到、但仍會造成 CI 間歇性失敗的不穩定測試特別有用。

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍會執行，但外掛程式會設定 `ignoreFailures = true`，並且只在非隔離的失敗發生時讓建置再次失敗。失敗仍會提供給不穩定測試偵測器，因此你可以在不破壞建置的情況下持續觀察該測試。選擇此模式用於你正在積極調查的測試。
- **略過**：外掛程式會透過 Gradle 的 `excludeTestsMatching` 將測試過濾掉，因此它永遠不會啟動。它不會產生新結果，並會從不穩定測試儀表板中移除，直到你重新啟用為止。當測試損壞、執行緩慢，或不穩定程度高到執行只是浪費 CI 分鐘數時，請選擇此模式。

<!-- @snippet: ./_quarantined-passing -->

### 啟用隔離 {#enabling-quarantine}

隔離會在 **CI 上自動啟用**（當設定 `CI` 環境變數時），並在本機建置中停用。外掛程式會在每個測試任務之前從 Tuist 伺服器取得隔離測試清單；靜音測試會正常執行並遮蔽其失敗，略過的測試則會被過濾掉。

你可以在你的 `settings.gradle.kts` 中明確控制此設定：

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

當未設定 `enabled` 時，預設為自動偵測：在 CI 上啟用，在本機停用。

## 對新測試進行壓力測試 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中執行，或未在已合併至該分支的提交上執行時，即視為新測試案例。在使用合併佇列時，一旦佇列的提交合併完成，佇列執行的測試案例就會被識別；若佇列將其移除，該測試案例仍保持為新狀態。提交是透過 Tuist 在 CI 上收集的 <.localized_link href="/guides/features/test-insights/gradle#git-history">Git 歷史記錄</.localized_link> 進行比對。

<!-- @snippet: ./_stress-modes -->

在 `settings.gradle.kts` 中宣告，或設定 `TUIST_TEST_STRESS_NEW_TESTS` 以針對每個 CI 管線調整模式：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

與隔離不同，此閘道沒有感知 CI 的預設值。若未設定 `mode`，它不會在任何地方執行。

<!-- @snippet: ./_stress-reruns -->

每次重試都是一個嵌套的 Gradle 建置，並過濾至該單一測試案例，因此每次重試都會獲得全新的測試 JVM。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
