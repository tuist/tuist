---
{
  "title": "Gradle 專案",
  "titleTemplate": ":title · 開始使用 · 指南 · Tuist",
  "description": "將 Gradle 專案連接至 Tuist，以取得共用的遠端建置快取、跨 CI 的建置與測試洞察、套件大小追蹤，以及預覽連結。"
}
---
# Gradle 專案 {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

依照此路徑，將現有的 Gradle 專案接入 Tuist。`dev.tuist` Gradle 外掛程式會將 Gradle 的本機建置快取連接到 Tuist 的遠端快取，並將建置與測試資料上傳至儀表板，全程無需更改任何 `./gradlew` 指令。

以下每個章節都會先說明目前缺少的功能，再逐步引導你使用能填補該空缺的功能。

## 前置需求

- 一個包含 `settings.gradle.kts`（或 `settings.gradle`）的 Gradle 專案。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

在 Gradle 專案根目錄執行 `tuist init`。選擇 **整合 Gradle 專案**，接著在瀏覽器中完成驗證，並選擇應擁有該專案的帳號。

```bash
tuist init
```

若由程式碼代理程式或腳本驅動此流程，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist 會在儲存庫根目錄寫入包含專案代號的 `tuist.toml`，並輸出一個 `plugins { ... }` 區塊。將其貼到 `settings.gradle.kts` 的頂部：

<!-- @snippet: ../_gradle-plugin-block -->

以 `./gradlew help` 進行健全性檢查。Gradle 應能無錯誤載入。若找不到外掛程式，請確認該區塊位於 `settings.gradle.kts`，而非 `build.gradle.kts`。

以下內容皆為可選且彼此獨立。

## 遠端建置快取

Gradle 的本機建置快取會將任務輸出儲存在產生它們的機器上。同一分支上的兩位開發者只會命中各自 `~/.gradle` 中的快取，而不會命中對方的；CI 則在每次作業中都會命中全新且空的快取。

Tuist 遠端快取擴充了 Gradle 已在跨機器使用的相同鍵/值協定。任務輸出會在上傳至首次執行該任務的機器，並由其他遇到相同輸入的任何使用者下載。在 `gradle.properties` 中啟用：

```properties
org.gradle.caching=true
```

接著在兩個環境中建置：

```bash
./gradlew clean build --build-cache --info
```

可快取的任務在第二次執行時會回報 `FROM-CACHE`。開啟儀表板上的 **快取** 查看隨時間變化的命中率。

## 建置洞察

Gradle 在建置結束時會輸出任務計時，並在使用 `--profile` 時寫入每次建置的 HTML 報告。兩者都不會跨執行聚合資料。在一系列提交中逐漸變慢的任務，在任何單一建置報告中看起來都與以往相同。

套用 `dev.tuist` 外掛程式後，它會自動將每次建置的任務計時上傳至儀表板。無需額外設定。在下一次執行 `./gradlew build` 後，開啟儀表板上的 **建置** 查看趨勢。

## 測試洞察

Gradle 的測試報告位於每次建置下的 `build/reports/tests/`。在十次 CI 執行中間歇性失敗的測試，在任何一份報告中看起來都像是一次偶然失敗的穩定測試。

測試洞察會記錄每次 `./gradlew test` 執行中每個任務的結果與持續時間，並跨執行關聯結果。不穩定測試、緩慢測試與失敗會顯示在儀表板的 **測試** 分頁。當不穩定情況累積時，從儀表板將其隔離，以免阻擋合併。

此外掛程式也支援 **壓力測試模式**，會重新執行建置引入的測試案例，並在它們合併前標記任何證實為不穩定的案例。將其加入 `settings.gradle.kts` 中的 `tuist` 擴充功能：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## 程式碼涵蓋率

JaCoCo 會為每個測試任務與每部機器寫入涵蓋率報告。沒有任何機制能合併某次提交的 CI 作業報告，或顯示分支的涵蓋率上升或下降。

此外掛程式可使用 JaCoCo 測量你的 JVM 與 Android 單元測試，並在每次測試執行時上傳涵蓋率。Tuist 會將某次提交的執行（包含分片）彙整為單一數值。在 `settings.gradle.kts` 中的 `tuist` 擴充功能中啟用：

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

開啟儀表板上的 **程式碼涵蓋率** 查看每次提交與每個檔案的資料。參閱 <.localized_link href="/guides/features/test-code-coverage/gradle">Gradle 程式碼涵蓋率</.localized_link> 了解如何在 CI 上完成提交以及 Robolectric 設定。

## 套件洞察

Android Gradle Plugin 會在建置輸出中回報產生的 `.aab` 大小。該數字會隨著分支消失，跨版本比較大小需要手動核算。Play Console 也會回報相同數字，但僅在構件上傳之後。

套件洞察會記錄每個 `.aab`（建議）或 `.apk` 的安裝與下載大小，並在超過每分支閾值時使 PR 檢查失敗。在建置步驟之後立即將此加入你的 CI：

```bash
tuist inspect bundle App.aab
```

開啟儀表板上的 **套件洞察 → Android** 查看趨勢並設定閾值。

## 預覽

Play Console 的內部測試軌道會在每次分享時增加審查與傳播延遲。透過 Slack 或電子郵件傳送原始 `.apk` 雖然較快，但會無法追蹤特定訊息所指涉的是哪一次建置。

此外掛程式可直接建置並發布應用程式變體，無需單獨的 CLI 上傳：

```bash
./gradlew :app:tuistShareDebug --track nightly
```

請求 `tuistShare<Variant>` 任務會讓該次呼叫選擇發布；一般建置永遠不會上傳預覽。參閱 <.localized_link href="/guides/features/previews/gradle">Gradle 預覽</.localized_link> 了解支援的 APK、簽署與安裝。

## 邀請團隊成員

快取命中、洞察與壓力測試的效果會隨著連接至專案的人數增加而累積。從儀表板的帳號設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `tuist auth login`。

對於 CI，請勿使用個人登入。使用你的 CI 提供者的 OIDC 身分進行驗證，或在儀表板中使用 **CI** 預設建立帳號權杖，並將其設為 `TUIST_TOKEN`。參閱 <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle 外掛程式驗證</.localized_link>。

## 完整外掛程式參考

以上內容涵蓋了在 Gradle 專案中從 Tuist 獲取價值所需的最低設定。`tuist` 擴充功能區塊、`stressNewTests` 模式以及 CI 驗證的設定選項，請參閱 [安裝 Gradle 外掛程式](https://tuist.dev/en/docs/guides/install-gradle-plugin) 參考文件。
