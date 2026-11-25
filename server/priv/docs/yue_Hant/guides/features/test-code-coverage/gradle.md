---
{
  "title": "Gradle 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳你嘅 Gradle 專案測試代碼覆蓋率（使用 JaCoCo 測量），並按檔案、專案同提交記錄追蹤。"
}
---
# Gradle 程式碼覆蓋率 {#gradle-code-coverage}

程式碼覆蓋率會告訴你測試執行了你程式碼中的哪些行。Tuist Gradle 外掛程式使用 JaCoCo 測量測試任務的覆蓋率，並在每次測試執行時上傳；Tuist 會將一個 commit 的所有執行合併為單一數值，涵蓋整個專案、每個 Gradle 專案以及每個檔案。儀表板的 **程式碼覆蓋率** 頁面會按 commit 顯示，並呈現每個分支的趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 已套用 `dev.tuist` Gradle 外掛程式，詳情請參閱 <.localized_link href="/guides/get-started/gradle-project">開始使用 Gradle 專案</.localized_link>
> - 你的專案位於 Git 儲存庫中：在非 Git 環境中執行會上傳測試結果，但不會上傳覆蓋率

## 設定 {#setup}

### 啟用覆蓋率 {#turn-coverage-on}

在你的 `settings.gradle.kts` 的 `tuist` 區塊中啟用覆蓋率：

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

或者，你可以透過環境變數為單一呼叫（例如 CI 工作）啟用覆蓋率；無論如何，環境變數的優先順序高於設定：

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

啟用與停用覆蓋率的測試任務會有獨立的建置快取項目（參見 [效能影響](#performance-impact)），因此當你的 CI 與本機建置共用建置快取時，建議使用設定檔：僅在 CI 中啟用覆蓋率可避免它們互相重用對方的測試結果。

啟用覆蓋率時，外掛程式會將 Gradle 的 `jacoco` 外掛程式套用到每個 JVM 專案。JaCoCo 的代理程式來自你專案的儲存庫，就像你自己套用該外掛程式一樣。已設定 JaCoCo 的專案會保留其設定，其自身的報告也會繼續運作。

外掛程式只報告你儲存庫中程式碼的覆蓋率，因此它將 JaCoCo 限制於此：除非測試任務自行設定 JaCoCo 的 `includes`，否則代理程式只會檢測你儲存庫所編譯類別的套件。相依套件、Android 框架以及你的測試框架會在未檢測的情況下執行，這能讓 JaCoCo 的資料以及測試任務的建置快取項目保持小巧。

### Android 專案 {#android-projects}

此外掛程式會測量 Android 專案的本機單元測試，例如 `testDebugUnitTest`。在裝置或模擬器上執行的檢測測試則不會被測量。

如果你的單元測試使用 Robolectric，請告訴 JaCoCo 包含 Robolectric 載入的類別。Robolectric 在其專屬的類別載入器中定義你應用程式的類別，而 JaCoCo 預設會跳過這類類別，因此這些測試執行的程式碼會顯示為未覆蓋。在 Android 專案的 `build.gradle.kts` 中：

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

此區塊僅在啟用覆蓋率時套用，因為此時外掛程式才會套用 `jacoco`。

Android 單元測試預設在 JUnit 4 上執行，這會記錄覆蓋率，但不會記錄 [每個測試執行了哪些程式碼](#per-test-evidence)。若要記錄，請透過 JUnit Vintage 在 JUnit Platform 上執行它們。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/gradle">對測試進行分片</.localized_link> 時，每個啟用覆蓋率執行的分片都會報告其所執行測試的覆蓋率，而 Tuist 會將一次執行的各個分片合併為單一數值。分片是刻意只執行測試套件的一部分，因此不會導致 commit 的覆蓋率不完整。

### 在 CI 上完成每個 commit {#complete-each-commit}

一個 commit 的覆蓋率通常來自多個工作，例如每個分片一個工作。Tuist 無法判斷最後一個工作何時已完成報告，因此需要你告知。當一個 commit 的所有測試工作都完成後，在依賴所有這些工作的另一個工作中執行以下指令：

```sh
./gradlew tuistCoverageComplete
```

當單一工作執行了一個 commit 的所有測試時，請改為在測試之後將該任務作為一個步驟執行，包括在測試失敗時：即使測試失敗，該次執行仍會報告其覆蓋率。

該任務會從檢出的 `HEAD` 讀取 commit，即你的測試所基於的 commit；傳遞 `-Ptuist.coverage.commit=<sha>` 以指定另一個 commit。在 commit 完成之前，其覆蓋率會顯示為 **進行中**，且不會納入其分支的趨勢中。

## 運作方式 {#how-it-works}

### Tuist 測量的內容 {#what-tuist-measures}

- **專案。** 每個 Gradle 專案在儀表板上都是一個模組，擁有各自的覆蓋率。
- **僅產品程式碼。** 從測試來源集編譯的類別屬於測試程式碼。Tuist 會儲存它們，但會將它們排除在所有數值之外。
- **你儲存庫中的檔案。** 一個類別會歸因於其編譯來源的原始檔，並依據其在儲存庫中的路徑計算。產生的原始碼以及被 Git 忽略的檔案不會被報告。
- **每行程式碼是否已執行。** JaCoCo 記錄程式碼是否已執行，而非執行次數，因此儀表板上的執行計數為 0 或 1。

### 每個測試執行了哪些程式碼 {#per-test-evidence}

對於在 JUnit Platform 上執行的測試（JUnit 5，或透過 JUnit Vintage 執行的 JUnit 4），外掛程式也會記錄每個測試執行了哪些程式碼，以及每個測試類別在其測試之外執行了什麼，例如在 `@BeforeAll` 中。這讓 Tuist 能夠延續被某次執行略過的測試所涵蓋的覆蓋率（參見 [略過的測試](#skipped-tests)）。無需對你的測試添加任何內容。

這在每個測試 JVM 一次執行一個測試時有效，除非你啟用 JUnit 的平行執行，否則 Gradle 預設就是如此執行測試。使用 `maxParallelForks` 在多個 JVM 中執行測試類別是可以的。在同一個 JVM 中同時執行的測試仍會計入覆蓋率，但無法個別區分。

### 建置快取 {#build-cache}

從建置快取還原或已是最新狀態的 Gradle 測試任務不會執行任何測試。其覆蓋率仍會上傳：JaCoCo 的資料是該任務的輸出之一，由在相同輸入上執行其測試的那次執行所記錄。

### 略過的測試 {#skipped-tests}

當某次執行略過測試時，只要它們執行的程式碼未變更，Tuist 就會從較早的執行中填入它們所涵蓋的內容。若無法做到，該 commit 的覆蓋率會標記為 **不完整**。某次執行可能略過的情況包括：

- **排除了某個專案的測試任務**，使用 `-x :app:test`。其測試會從最近一次執行且程式碼未變更的結果中延續。
- **部分專案的測試**，使用 `./gradlew :core:test`，或 **部分測試**，使用 `--tests`。該次執行僅涵蓋你要求的範圍，因此除非該 commit 的另一次執行執行了所有內容，否則該 commit 會被視為不完整。
- **在首次失敗時停止的測試任務**（`failFast`）。

有些測試是刻意略過，且不會導致 commit 不完整：

- **建置腳本中的篩選器**，例如 `filter { excludeTestsMatching(...) }`，用於定義測試套件的執行範圍。
- **建置腳本停用的測試任務**，透過 `enabled = false` 或會略過它們的 `onlyIf` 設定。
- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle">隔離</.localized_link> 略過的測試。** 它們會被排除，猶如已被移除，因此僅由它們涵蓋的程式碼行會被視為未涵蓋。
- **其他分片的測試**，當你 [對測試進行分片](#sharded-runs) 時。

### 完整與不完整的 commit {#commit-status}

| 狀態 | 意義 |
| --- | --- |
| 進行中 | 已有執行回報覆蓋率，但尚未針對該 commit 執行 `tuistCoverageComplete`。 |
| 完整 | 該 commit 所有執行的測試均已執行、已延續，或是刻意略過。 |
| 不完整 | 部分覆蓋率無法確定，因此該數值為下限。 |
| 未測量 | 沒有任何執行針對該 commit 回報覆蓋率。 |

分支趨勢僅包含完整的 commit。

## 效能影響 {#performance-impact}

JaCoCo 會在測試 JVM 載入類別時對其进行检测，因此無論是否啟用覆蓋率，你編譯的類別與編譯任務的建置快取項目都保持不變。讀取每個依賴項配置的任務（例如 SBOM 產生器）也會偵測到 JaCoCo 代理程式，因此當你啟用覆蓋率時，它們的輸出會有所改變。測試執行速度會稍慢，且外掛程式會在測試任務完成後讀取 JaCoCo 的資料。啟用與停用覆蓋率的測試任務擁有獨立的建置快取項目，因此即使未啟用覆蓋率的結果已被快取，首次啟用覆蓋率的執行仍會實際執行測試。

## 限制 {#limitations}

- **獨立專案與隨需配置。** 這些建置不會配置每個專案，因此外掛程式無法判斷某次執行略過了哪些專案的測試，而僅執行部分專案測試的執行會被視為完整。
- **來自 Fork 的 Pull Request 不會提供覆蓋率。** 只有通過 Tuist 驗證的執行才會上傳覆蓋率，而 CI 通常會對來自 Fork 的 Pull Request 隱藏密鑰與身分令牌。

## 查詢覆蓋率 {#querying}

儀表板的 **程式碼覆蓋率** 頁面顯示每個 commit 的數值、其模組與檔案，以及每次執行所涵蓋的程式碼行。相同的資料也可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 伺服器</.localized_link> 提供給代理程式使用。
