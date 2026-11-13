---
{
  "title": "Gradle 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 偵測、管理並隔離 Gradle 專案中的不穩定測試。"
}
---
# Gradle 不穩定測試 {#gradle-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 已設定<.localized_link href="/guides/features/test-insights/gradle">Gradle 測試洞察</.localized_link>。

<!-- @snippet: ./_intro -->

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測的運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你執行具備重試功能的測試時，Tuist 會分析每次嘗試的結果。如果某個測試在某些嘗試中失敗，但在其他嘗試中通過，就會被標記為不穩定。

你可以使用[Test Retry 外掛程式](https://github.com/gradle/test-retry-gradle-plugin)或類似機制來重新執行失敗的測試。Tuist 會偵測到那些在某些嘗試中通過、但在其他嘗試中失敗的測試。

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

即使沒有測試重試，Tuist 也能透過比較同一個提交與同一個 Gradle 專案在不同 CI 執行中的結果，來偵測不穩定測試。如果某個測試在一次 CI 執行中通過，但在相同提交與專案的另一次執行中失敗，該失敗的執行就會被標記為不穩定。

Gradle 專案是比較鍵的一部分，因為同一個測試在不同專案中可能呈現確定性但不同的行為——例如，一個共用測試類別以不同的相依性編譯，或在不同的模組固定裝置上執行。同一個提交在不同 Gradle 專案上的兩次執行會被視為獨立的執行變體，彼此不會標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試機制抓到、但仍會造成間歇性 CI 失敗的不穩定測試特別有用。

<!-- @snippet: ./_managing -->

## 隔離不穩定測試 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍會執行，但外掛程式會設定 `ignoreFailures = true`，並且只在出現非隔離失敗時讓建置再次失敗。失敗紀錄仍會提供給不穩定測試偵測器，因此你可以在不破壞建置的情況下持續觀察該測試。若你正在積極調查某個測試，請選擇此模式。
- **略過**：外掛程式會透過 Gradle 的 `excludeTestsMatching` 將測試過濾掉，因此它永遠不會啟動。它不會產生新的結果，並會從不穩定測試儀表板中移除，直到你重新啟用為止。當測試損壞、執行緩慢，或不穩定情況嚴重到執行只會浪費 CI 分鐘數時，請選擇此模式。

<!-- @snippet: ./_quarantined-passing -->

### 啟用隔離 {#enabling-quarantine}

隔離會在 **CI 環境中自動啟用**（當設定 `CI` 環境變數時），並在本機建置中停用。外掛程式會在每個測試任務之前從 Tuist 伺服器取得隔離測試清單；靜音測試會正常執行並遮蔽其失敗，略過的測試則會被過濾掉。

你可以在 `settings.gradle.kts` 中明確控制此行為：

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

當未設定 `enabled` 時，預設為自動偵測：在 CI 中啟用，在本機中停用。

## 對新測試進行壓力測試 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中執行，或未在已合併至該分支的提交上執行時，即視為新測試案例。使用合併佇列時，佇列執行的測試案例會在佇列的提交合併後被識別，若佇列將其移除，則仍維持為新測試。提交會透過 Tuist 在 CI 上收集的<.localized_link href="/guides/features/test-insights/gradle#git-history">Git 歷史記錄</.localized_link>進行比對。

<!-- @snippet: ./_stress-modes -->

在 `settings.gradle.kts` 中宣告，或設定 `TUIST_TEST_STRESS_NEW_TESTS` 以針對不同 CI 管道調整模式：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

與隔離不同，此閘道沒有感知 CI 的預設值。若未設定 `mode`，則不會在任何地方執行。

<!-- @snippet: ./_stress-reruns -->

每次重新執行都是一個巢狀 Gradle 建置，並過濾至該單一測試案例，因此每次重新執行都會獲得全新的測試 JVM。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
