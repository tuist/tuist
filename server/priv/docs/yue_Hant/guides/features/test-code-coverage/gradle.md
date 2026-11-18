---
{
  "title": "Gradle 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳使用 JaCoCo 量度的 Gradle 專案測試代碼覆蓋率，並按檔案、專案及提交追蹤。"
}
---
# Gradle 代碼覆蓋率 {#gradle-code-coverage}

代碼覆蓋率會告訴你測試執行了代碼中的哪些行。Tuist Gradle 外掛程式使用 JaCoCo 測量測試任務的覆蓋率，並在每次測試執行時上傳；Tuist 會將一個 commit 的所有執行合併為單一數值，涵蓋整個專案、每個 Gradle 專案以及每個檔案。儀表板的 **代碼覆蓋率** 頁面會按 commit 顯示，並呈現每個分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 已套用 `dev.tuist` Gradle 外掛程式，詳情請參閱 <.localized_link href="/guides/get-started/gradle-project">開始使用 Gradle 專案</.localized_link>
> - 你的專案位於 Git 儲存庫中：在非 Git 環境中執行會上傳測試結果，但不會上傳覆蓋率

## 設定 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

在 `settings.gradle.kts` 的 `tuist` 區塊中開啟覆蓋率：

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

或者透過環境變數為單次呼叫（例如 CI 工作）開啟覆蓋率，此設定的優先級高於上述設定：

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

開啟與關閉覆蓋率的測試任務會有獨立的建構快取項目（參見 [效能影響](#performance-impact)），因此當你的 CI 和本地建構共用建構快取時，建議使用設定檔方式：僅在 CI 中開啟覆蓋率可防止它們互相重用彼此的測試結果。

開啟覆蓋率時，外掛程式會將 Gradle 的 `jacoco` 外掛程式套用到每個 JVM 專案。JaCoCo agent 會來自你專案的 repositories，就像你自己套用該外掛程式一樣。已設定 JaCoCo 的專案會保留其設定，且其原有的報告仍可正常運作。

### Android 專案 {#android-projects}

外掛程式會測量 Android 專案的本機單元測試，例如 `testDebugUnitTest`。在裝置或模擬器上執行的插樁測試則不會被測量。

如果你的單元測試使用 Robolectric，請告訴 JaCoCo 包含 Robolectric 載入的類別。Robolectric 在其自己的類別載入器中定義應用程式的類別，而 JaCoCo 預設會跳過這些類別，導致這些測試執行的代碼顯示為未覆蓋。在 Android 專案的 `build.gradle.kts` 中：

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

此區塊僅在開啟覆蓋率時生效，因為此時外掛程式才會套用 `jacoco`。

Android 單元測試預設在 JUnit 4 上執行，這會記錄覆蓋率，但不會記錄 [每個測試執行了哪些代碼](#per-test-evidence)。若要記錄，請透過 JUnit Vintage 在 JUnit Platform 上執行它們。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/gradle">對測試進行分片</.localized_link> 時，每個開啟覆蓋率執行的分片都會報告其測試的覆蓋率，而 Tuist 會將一次執行的所有分片合併為單一數值。分片刻意只執行套件的一部分，因此不會導致 commit 的覆蓋率不完整。

### 在 CI 中完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個工作，例如每個分片一個工作。Tuist 無法判斷最後一個工作何時完成報告，因此需要你告知。當一個 commit 的所有測試工作完成後，在依賴所有這些工作的工作中執行以下指令：

```sh
./gradlew tuistCoverageComplete
```

當單一工作執行一個 commit 的所有測試時，請改為在測試之後將此任務作為一個步驟執行，包括測試失敗時：即使測試失敗，執行仍會報告其覆蓋率。

任務會從 `GIT_COMMIT` 或 checkout 的 `HEAD` 讀取 commit；傳遞 `-Ptuist.coverage.commit=<sha>` 以指定另一個 commit。在 commit 完成之前，其覆蓋率會顯示為 **進行中**，且不會納入該分支的趨勢。

## 運作原理 {#how-it-works}

### Tuist 測量的內容 {#what-tuist-measures}

- **專案。** 每個 Gradle 專案在儀表板上都是一個模組，擁有各自的覆蓋率。
- **僅產品代碼。** 從測試來源集編譯的類別屬於測試代碼。Tuist 會儲存它們，但將其排除在所有數值之外。
- **你儲存庫中的檔案。** 類別會計入其編譯來源的原始檔，並依據其在儲存庫中的路徑歸類。產生的來源和 Git 忽略的檔案不會被報告。
- **每行代碼是否執行。** JaCoCo 記錄代碼是否執行，而非執行次數，因此儀表板上的執行計數為 0 或 1。

### 每個測試執行了哪些代碼 {#per-test-evidence}

對於在 JUnit Platform 上執行的測試（JUnit 5，或透過 JUnit Vintage 執行的 JUnit 4），外掛程式還會記錄每個測試執行了哪些代碼，以及每個測試類別在其測試之外執行了什麼，例如在 `@BeforeAll` 中。這讓 Tuist 能夠沿用被執行略過的測試所涵蓋的覆蓋率（參見 [略過的測試](#skipped-tests)）。無需對你的測試添加任何內容。

這在每個測試 JVM 一次執行一個測試時有效，除非你開啟 JUnit 的平行執行，否則 Gradle 就是這樣執行測試。使用 `maxParallelForks` 在多個 JVM 中執行測試類別是可以的。在同一個 JVM 中同時執行的測試仍會計入覆蓋率，但無法個別區分。

### 建構快取 {#build-cache}

Gradle 從建構快取還原的測試任務，或已是最新的任務，不會執行任何測試。其覆蓋率仍會上傳：JaCoCo 的數據是任務的輸出之一，由在相同輸入上執行其測試的執行所記錄。

### 略過的測試 {#skipped-tests}

當一次執行略過某些測試時，只要它們執行的代碼未變更，Tuist 就會從之前的執行中填入它們涵蓋的內容。若無法做到，該 commit 的覆蓋率會標示為 **不完整**。執行略過的情況包括：

- **排除專案的測試任務**，使用 `-x :app:test`。其測試會從代碼未變更的上次執行中沿用。
- **部分專案的測試**，使用 `./gradlew :core:test`，或使用 `--tests` 指定 **部分測試**。該執行僅涵蓋你要求的內容，因此除非該 commit 的另一次執行運行了所有內容，否則 commit 將不完整。
- **在首次失敗時停止的測試任務**（`failFast`）。

有些測試是刻意略過的，不會導致 commit 不完整：

- **建構腳本中的過濾器**，例如 `filter { excludeTestsMatching(...) }`，它們定義了套件執行的內容。
- **建構腳本關閉的測試任務**，透過 `enabled = false` 或會略過它們的 `onlyIf`。
- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle">隔離</.localized_link> 略過的測試。** 它們會被略過，猶如已被移除，因此僅由它們涵蓋的代碼行會被視為未涵蓋。
- **其他分片的測試**，當你 [將測試分片](#sharded-runs) 時。

### 完整與不完整的 commit {#commit-status}

| 狀態 | 意義 |
| --- | --- |
| 進行中 | 已有執行回報覆蓋率，但該 commit 尚未執行 `tuistCoverageComplete`。 |
| 完整 | 該 commit 所有執行的測試均已執行、沿用或刻意略過。 |
| 不完整 | 部分覆蓋率無法確定，因此該數值為下限。 |
| 未測量 | 沒有執行為該 commit 回報覆蓋率。 |

分支趨勢僅包含完整的 commit。

## 效能影響 {#performance-impact}

JaCoCo 會在測試 JVM 載入類別時對其进行检测，因此無論是否開啟覆蓋率，你編譯的類別和編譯任務的建構快取項目都保持不變。讀取每個依賴設定的任務（例如 SBOM 產生器）也會偵測到 JaCoCo 代理程式，因此當你開啟覆蓋率時，它們的輸出會改變。測試執行速度會稍慢，且外掛程式會在測試任務完成後讀取 JaCoCo 的數據。開啟和關閉覆蓋率的測試任務擁有獨立的建構快取項目，因此即使未開啟覆蓋率的結果已快取，首次開啟覆蓋率的執行仍會執行測試。

## 限制 {#limitations}

- **孤立專案與按需設定。** 這些建構不會設定每個專案，因此外掛程式無法判斷執行略過了哪些專案的測試，而執行部分專案的測試會被視為完整。
- **來自 fork 的 pull request 沒有覆蓋率。** 只有透過 Tuist 驗證的執行才會上傳覆蓋率，而 CI 通常會對來自 fork 的 pull request 隱藏密鑰和身份令牌。

## 查詢覆蓋率 {#querying}

儀表板的 **代碼覆蓋率** 頁面顯示每個 commit 的數值、其模組及其檔案，並列出每次執行涵蓋的代碼行。代理人可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 存取相同的數據。
