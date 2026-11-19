---
{
  "title": "Gradle 程式碼涵蓋率",
  "titleTemplate": ":title · 程式碼涵蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳 Gradle 專案測試的程式碼涵蓋率（使用 JaCoCo 測量），並按檔案、專案和提交追蹤。"
}
---
# Gradle 程式碼涵蓋率 {#gradle-code-coverage}

程式碼涵蓋率告訴你測試執行了程式碼中的哪些行。Tuist Gradle 外掛程式使用 JaCoCo 測量測試工作的涵蓋率，並在每次測試執行時上傳；Tuist 會將一個提交的多次執行合併為單一數值，分別適用於專案、每個 Gradle 專案以及每個檔案。儀表板的 **程式碼涵蓋率** 頁面會顯示每個提交的數據，並呈現每個分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 已套用 `dev.tuist` Gradle 外掛程式，如 <.localized_link href="/guides/get-started/gradle-project">開始使用 Gradle 專案</.localized_link> 中所述
> - 你的專案位於 Git 儲存庫中：在非 Git 環境中執行會上傳測試結果，但不包含涵蓋率

## 設定 {#setup}

### 開啟涵蓋率 {#turn-coverage-on}

在 `settings.gradle.kts` 的 `tuist` 區塊中開啟涵蓋率：

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

或者，透過環境變數為單次呼叫（例如 CI 工作）開啟涵蓋率，其優先順序高於上述設定：

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

開啟與關閉涵蓋率的測試工作擁有獨立的建置快取項目（參見 [效能影響](#performance-impact)），因此當你的 CI 與本機建置共用建置快取時，建議使用設定檔：僅在 CI 中開啟涵蓋率可防止它們互相重用彼此的測試結果。

開啟涵蓋率時，外掛程式會將 Gradle 的 `jacoco` 外掛程式套用到每個 JVM 專案。JaCoCo 代理程式來自你專案的儲存庫，就像你自己套用該外掛程式一樣。已設定 JaCoCo 的專案會保留其設定，且其原有的報告仍可正常運作。

### Android 專案 {#android-projects}

此外掛程式會測量 Android 專案的本機單元測試，例如 `testDebugUnitTest`。在裝置或模擬器上執行的插樁測試則不會被測量。

如果你的單元測試使用 Robolectric，請告訴 JaCoCo 納入 Robolectric 載入的類別。Robolectric 在其專屬的類別載入器中定義你的應用程式類別，而 JaCoCo 預設會跳過此類類別，導致這些測試執行的程式碼顯示為未涵蓋。在 Android 專案的 `build.gradle.kts` 中：

```kotlin
pluginManager.withPlugin("jacoco") {
    tasks.withType<Test>().configureEach {
        extensions.configure<JacocoTaskExtension> {
            isIncludeNoLocationClasses = true
            excludes = listOf("jdk.internal.*")
        }
    }
}
```

此區塊僅在開啟涵蓋率時生效，因為此時外掛程式才會套用 `jacoco`。

Android 單元測試預設在 JUnit 4 上執行，這會記錄涵蓋率，但不會記錄 [每個測試執行了哪些程式碼](#per-test-evidence)。若要記錄此資訊，請透過 JUnit Vintage 在 JUnit Platform 上執行它們。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/gradle">對測試進行分片</.localized_link> 時，每個開啟涵蓋率執行的分片都會回報其測試的涵蓋率，而 Tuist 會將一次執行的各個分片合併為單一數值。分片旨在執行套件的一部分，因此不會導致提交的涵蓋率不完整。

### 在 CI 上完成每個提交 {#complete-each-commit}

提交的涵蓋率通常來自多個工作，例如每個分片一個工作。Tuist 無法判斷最後一個工作何時已完成回報，因此需要你明確告知。當某個提交的所有測試工作完成後，在依賴所有這些工作的工作中執行以下指令：

```sh
./gradlew tuistCoverageComplete
```

當單一工作執行某個提交的所有測試時，請改為在測試之後將此任務作為一個步驟執行，即使測試失敗也需執行：包含失敗測試的執行仍然會回報其涵蓋率。

此任務從 `GIT_COMMIT` 或檢出的 `HEAD` 讀取提交；傳遞 `-Ptuist.coverage.commit=<sha>` 以指定其他提交。在提交完成之前，其涵蓋率會顯示為 **進行中**，且不會納入該分支的趨勢中。

## 運作方式 {#how-it-works}

### Tuist 測量的內容 {#what-tuist-measures}

- **專案。** 每個 Gradle 專案在儀表板上都是一個模組，擁有各自的涵蓋率。
- **僅產品程式碼。** 從測試來源集編譯的類別屬於測試程式碼。Tuist 會儲存它們，但將其排除在所有數值之外。
- **你儲存庫中的檔案。** 類別歸屬於其編譯來源的原始檔，路徑對應你儲存庫中的位置。產生的原始碼和 Git 忽略的檔案不會被回報。
- **每行是否已執行。** JaCoCo 記錄程式碼是否執行過，而非執行次數，因此儀表板上的執行計數為 0 或 1。

### 每個測試執行了哪些程式碼 {#per-test-evidence}

對於在 JUnit Platform 上執行的測試（JUnit 5，或透過 JUnit Vintage 執行的 JUnit 4），外掛程式也會記錄每個測試執行了哪些程式碼，以及每個測試類別在測試之外執行了什麼，例如在 `@BeforeAll` 中。這讓 Tuist 能夠沿用被執行略過的測試之涵蓋率（參見 [略過的測試](#skipped-tests)）。無需對你的測試添加任何內容。

這在每個測試 JVM 一次執行一個測試時有效，除非你開啟 JUnit 的平行執行，否則 Gradle 預設以此方式執行測試。使用 `maxParallelForks` 在多個 JVM 中執行測試類別是可以的。在同一個 JVM 中同時執行的測試仍會計入涵蓋率，但無法個別區分。

### 建置快取 {#build-cache}

Gradle 從建置快取還原的測試工作，或已是最新狀態的工作，不會執行任何測試。其涵蓋率仍會上傳：JaCoCo 的數據是該工作的輸出之一，由在相同輸入上執行其測試的那次執行所記錄。

### 略過的測試 {#skipped-tests}

當某次執行略過測試時，只要它們執行的程式碼未變更，Tuist 就會從之前的執行中填入它們所涵蓋的內容。若無法做到，該提交的涵蓋率將標記為 **不完整**。執行略過的情況包括：

- **排除了專案的測試工作**，使用 `-x :app:test`。其測試會從程式碼未變更的上次執行中沿用。
- **部分專案的測試**，使用 `./gradlew :core:test`，或使用 `--tests` 針對 **部分測試**。該執行僅涵蓋你要求的內容，因此除非該提交的其他執行運行了所有內容，否則提交將不完整。
- **在首次失敗時停止的測試工作**（`failFast`）。

某些測試是故意略過的，不會導致提交不完整：

- **建置腳本中的篩選器**，例如 `filter { excludeTestsMatching(...) }`，它們定義了你的套件要執行哪些測試。
- **建置腳本停用的測試工作**，使用 `enabled = false` 或會略過它們的 `onlyIf`。
- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle">隔離</.localized_link> 略過的測試。** 它們會被視為已移除而略過，因此僅由它們涵蓋的行數將計為未涵蓋。
- **其他分片的測試**，當你 [對測試進行分片](#sharded-runs) 時。

### 完整與不完整的提交 {#commit-status}

| 狀態 | 意義 |
| --- | --- |
| 進行中 | 已有執行回報涵蓋率，但該提交尚未執行 `tuistCoverageComplete`。 |
| 完整 | 該提交之所有執行的測試皆已執行、沿用或故意略過。 |
| 不完整 | 部分涵蓋率無法判定，因此該數值為下限。 |
| 未測量 | 沒有執行回報該提交的涵蓋率。 |

分支趨勢僅包含完整的提交。

## 效能影響 {#performance-impact}

JaCoCo 會在測試 JVM 載入類別時對其进行检测，因此無論是否開啟涵蓋率，你編譯的類別與編譯工作的建置快取項目都保持不變。讀取每個相依性設定的工作（例如 SBOM 產生器）也會看到 JaCoCo 代理程式，因此當你開啟涵蓋率時，它們的輸出會改變。測試執行速度會稍慢，且外掛程式會在測試工作完成後讀取 JaCoCo 數據。開啟與關閉涵蓋率的測試工作擁有獨立的建置快取項目，因此即使未開啟涵蓋率的結果已被快取，首次開啟涵蓋率的執行仍會執行測試。

## 限制 {#limitations}

- **隔離專案與隨需設定。** 這些建置不會設定每個專案，因此外掛程式無法判斷某次執行略過了哪些專案的測試，而僅執行部分專案測試的執行會被計為完整。
- **來自分叉的拉取請求沒有涵蓋率。** 只有透過 Tuist 驗證的執行才會上傳涵蓋率，而 CI 通常會對來自分叉的拉取請求隱藏機密與身分令牌。

## 查詢涵蓋率 {#querying}

儀表板的 **程式碼涵蓋率** 頁面顯示每個提交的數值、其模組與檔案，以及每次執行涵蓋的行數。相同的數據可透過 <.localized_link href="/guides/features/agentic-coding/mcp">模型上下文協定伺服器</.localized_link> 提供給代理程式使用。
