---
{
  "title": "Gradle 代碼覆蓋率",
  "titleTemplate": ":title · 代碼覆蓋率 · 功能 · 指南 · Tuist",
  "description": "上傳以 JaCoCo 量度嘅 Gradle 專案測試代碼覆蓋率，並按檔案、專案同提交追蹤。"
}
---
# Gradle 程式碼覆蓋率 {#gradle-code-coverage}

程式碼覆蓋率會告訴你測試執行咗邊啲代碼行。Tuist Gradle plugin 會用 JaCoCo 量度你測試任務嘅覆蓋率，並喺每次測試執行時上傳；Tuist 會將一個 commit 嘅多次執行合併成單一數值，涵蓋整個項目、每個 Gradle project 同每份檔案。Dashboard 嘅 **Code Coverage** 頁面會按 commit 顯示，並呈現每個分支嘅趨勢。

> [!IMPORTANT]
> **必要條件**
>
> - 已套用 `dev.tuist` Gradle plugin，詳情請參閱 <.localized_link href="/guides/get-started/gradle-project">開始使用 Gradle 項目</.localized_link>
> - 你嘅項目位於 Git 儲存庫：喺儲存庫之外執行會上傳測試結果，但唔會上傳覆蓋率數據

## 設定 {#setup}

### 開啟覆蓋率 {#turn-coverage-on}

喺你 `settings.gradle.kts` 嘅 `tuist` 區塊中開啟覆蓋率：

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

或者透過環境變數為單次調用（例如 CI 工作）開啟，此設定會優先於上述設定：

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

開啟覆蓋率後，plugin 會將 Gradle 嘅 `jacoco` plugin 套用至每個 JVM project。JaCoCo agent 會從你項目嘅 repositories 取得，就好似你自己套用 plugin 一樣。如果項目已經設定咗 JaCoCo，就會保留原有設定，其報告亦會繼續正常運作。

### 分片執行 {#sharded-runs}

當你 <.localized_link href="/guides/features/test-sharding/gradle">將測試分片</.localized_link> 時，每個開啟覆蓋率執行嘅分片都會回報其所運行測試嘅覆蓋率，而 Tuist 會將一次執行嘅各個分片合併成單一數值。分片係故意只運行測試套件嘅一部分，因此唔會令 commit 嘅覆蓋率變得 incomplete。

### 喺 CI 完成每個 commit {#complete-each-commit}

一個 commit 嘅覆蓋率通常來自多個工作，例如每個分片一個工作。Tuist 無法判斷最後一個工作何時已完成回報，所以你需要主動通知。當某個 commit 嘅所有測試工作都完成後，喺一個依賴晒所有該等工作嘅工作中執行以下指令：

```sh
./gradlew tuistCoverageComplete
```

該任務會從 `GIT_COMMIT` 或 checkout 嘅 `HEAD` 讀取 commit；如需指定其他 commit，請傳遞 `-Ptuist.coverage.commit=<sha>`。喺 commit 未完成之前，其覆蓋率會顯示為 **In progress**，並且唔會計入該分支嘅趨勢。

## 運作原理 {#how-it-works}

### Tuist 量度乜嘢 {#what-tuist-measures}

- **Projects。** 每個 Gradle project 喺 dashboard 上都是一個 module，擁有自己嘅覆蓋率。
- **只計產品代碼。** 由測試 source sets 編譯嘅 classes 屬於測試代碼。Tuist 會儲存佢哋，但唔會將佢哋計入任何數值。
- **你儲存庫嘅檔案。** 一個 class 會歸入其編譯來源嘅原始檔，並按照其喺你儲存庫中嘅路徑計算。Generated sources 同被 Git ignore 嘅檔案唔會被報告。
- **每行代碼有否執行。** JaCoCo 只會記錄代碼有否執行，而唔係執行次數，因此 dashboard 上嘅執行次數為 0 或 1。

### 每個測試執行咗邊啲代碼 {#per-test-evidence}

對於喺 JUnit Platform 上運行嘅測試（JUnit 5，或透過 JUnit Vintage 運行嘅 JUnit 4），plugin 亦會記錄每個測試執行咗邊啲代碼，以及每個測試 class 喺測試之外執行咗乜嘢（例如喺 `@BeforeAll` 中）。這讓 Tuist 能夠沿用被某次執行略過嘅測試所涵蓋嘅覆蓋率（見 [Skipped tests](#skipped-tests)）。你唔需要對測試做任何額外設定。

這喺每個測試 JVM 一次只運行一個測試時生效，除非你開啟 JUnit 嘅平行執行，否則 Gradle 就係咁樣運行測試。使用 `maxParallelForks` 喺多個 JVM 中運行測試 class 係冇問題嘅。喺同一個 JVM 中同時運行嘅測試仍然會計入覆蓋率，但唔會個別分開計算。

### Build cache {#build-cache}

從 build cache 恢復或已 up to date 嘅測試任務唔會運行任何測試。但其覆蓋率仍然會上傳：JaCoCo 數據係任務嘅輸出之一，由喺相同輸入下執行其測試嘅那次執行所記錄。

### Skipped tests {#skipped-tests}

當某次執行略過部分測試時，只要佢哋執行嘅代碼冇改變，Tuist 就會從較早嘅執行中填入佢哋涵蓋嘅範圍。如果做唔到，該 commit 嘅覆蓋率就會顯示為 **Incomplete**。某次執行會略過以下內容：

- **排除咗某個 project 嘅測試任務**，使用 `-x :app:test`。其測試會從代碼未改變嘅最後一次執行中沿用。
- **部分 project 嘅測試**，使用 `./gradlew :core:test`；或者 **部分測試**，使用 `--tests`。該次執行只涵蓋你要求嘅部分，因此除非該 commit 嘅另一次執行運行咗所有測試，否則該 commit 會被視為 incomplete。
- **喺首次失敗時停止嘅測試任務**（`failFast`）。

部分測試係故意略過，唔會令 commit 變成 incomplete：

- **你 build script 中嘅過濾器**，例如 `filter { excludeTestsMatching(...) }`，用於定義你嘅測試套件運行邊啲測試。
- **被你 build script 停用嘅測試任務**，透過 `enabled = false` 或會略過佢哋嘅 `onlyIf`。
- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle">quarantine</.localized_link> 略過嘅測試。** 佢哋會被略過，就好似被刪除咗一樣，因此只有佢哋涵蓋嘅行會被計為未覆蓋。
- **其他分片嘅測試**，當你 [將測試分片](#sharded-runs) 時。

### Complete 同 Incomplete commits {#commit-status}

| 狀態 | 含義 |
| --- | --- |
| 進行中 | 已有執行匯報覆蓋率，但 `tuistCoverageComplete` 尚未為該 commit 運行。 |
| Complete | 該 commit 所有執行中嘅每個測試都已運行、已沿用或已故意略過。 |
| Incomplete | 部分覆蓋率無法確定，因此該數字只係下限。 |
| 未測量 | 冇任何執行為該 commit 匯報覆蓋率。 |

分支趨勢只包含 complete commits。

## 效能影響 {#performance-impact}

JaCoCo 喺測試 JVM 載入 class 時對其進行檢測，因此無論開啟或關閉覆蓋率，你編譯好嘅 class 同編譯任務嘅 build cache entries 都保持不變。讀取每個依賴配置嘅任務（例如 SBOM 產生器）亦會見到 JaCoCo agent，因此當你開啟覆蓋率時，佢哋嘅輸出會改變。測試運行速度會稍慢，插件會喺測試任務完成後讀取 JaCoCo 數據。開啟同關閉覆蓋率嘅測試任務有獨立嘅 build cache entries，因此即使冇覆蓋率嘅結果已被快取，第一次開啟覆蓋率嘅執行仍然會執行測試。

## 限制 {#limitations}

- **Isolated Projects 同按需配置。** 呢類 build 唔會配置每個 project，因此插件無法判斷某次執行略過咗邊啲 project 嘅測試，而運行部分 project 測試嘅執行會被視為 complete。
- **來自 fork 嘅 pull request 冇覆蓋率。** 只有通過 Tuist 認證嘅執行先會上傳覆蓋率，而 CI 通常會喺來自 fork 嘅 pull request 中扣留 secrets 同身份令牌。

## 查詢覆蓋率 {#querying}

Dashboard 嘅 **Code Coverage** 頁面顯示每個 commit 嘅數據、其 modules 同 files，以及每次執行涵蓋嘅行。Agent 可以透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link> 存取相同數據。
