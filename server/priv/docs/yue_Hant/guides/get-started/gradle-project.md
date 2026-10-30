---
{
  "title": "Gradle 專案",
  "titleTemplate": ":title · 入門指南 · 教學指南 · Tuist",
  "description": "將 Gradle 專案連接至 Tuist，以使用共享遠端建置快取、跨 CI 取得建置與測試洞察、追蹤套件大小，並提供預覽連結。"
}
---
# Gradle 專案 {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

按照以下步驟，將現有 Gradle 專案連接到 Tuist。`dev.tuist` Gradle 外掛程式會將 Gradle 的本機建置快取連接至 Tuist 的遠端快取，並將建置和測試資料上傳到儀表板，全程無需更改任何 `./gradlew` 指令。

以下每個章節都會先說明目前缺少的功能，再逐步介紹填補該空缺的功能。

## 必要條件

- 一個包含 `settings.gradle.kts`（或 `settings.gradle`）的 Gradle 專案。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

在 Gradle 專案根目錄執行 `tuist init`。選擇 **整合 Gradle 專案**，然後在瀏覽器中進行驗證，並選擇應擁有該專案的帳戶。

```bash
tuist init
```

如果你透過編碼代理程式或腳本執行此操作，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），然後使用非互動式形式：

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist 會在儲存庫根目錄寫入包含專案代號的 `tuist.toml`，並輸出 `plugins { ... }` 區塊。將其貼到 `settings.gradle.kts` 的頂部：

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

使用 `./gradlew help` 進行健全性檢查。Gradle 應該能無錯誤載入。如果找不到外掛程式，請確認該區塊位於 `settings.gradle.kts`，而非 `build.gradle.kts`。

以下所有內容皆為可選且獨立。

## 遠端建置快取

Gradle 的本機建置快取會在產生輸出的機器上儲存任務輸出。同一分支上的兩位開發者只會命中各自 `~/.gradle` 中的快取，而不會命中對方的；CI 則會在每次作業時命中全新的空快取。

Tuist 遠端快取擴充了 Gradle 已在跨機器使用的相同鍵/值協定。任務輸出會在上傳至首次執行該任務的機器，而其他遇到相同輸入的使用者則會下載這些輸出。在 `gradle.properties` 中啟用：

```properties
org.gradle.caching=true
```

然後在兩個環境中建置：

```bash
./gradlew clean build --build-cache --info
```

可快取的任務在第二次執行時會回報 `FROM-CACHE`。開啟儀表板上的 **快取** 以查看隨時間變化的命中率。

## 建置洞察

Gradle 會在建置結束時發出任務計時，並透過 `--profile` 撰寫每份建置的 HTML 報告。兩者都不會跨執行匯總。隨著一系列提交而變慢的任務，在任何單一建置報告中看起來都與以往相同。

套用外掛程式後，`dev.tuist` 外掛程式會自動將每次建置的任務計時上傳至儀表板。無需額外設定。在下一次 `./gradlew build` 之後，開啟儀表板上的 **建置** 以查看趨勢。

## 測試洞察

Gradle 的測試報告位於每份建置下的 `build/reports/tests/`。在十次 CI 執行中間歇性失敗的測試，在任何一份報告中看起來都像是一次偶然失敗的穩定測試。

測試洞察會記錄每次 `./gradlew test` 執行的每個任務結果和持續時間，並跨執行關聯結果。不穩定測試、緩慢測試和失敗會顯示在儀表板的 **測試** 分頁。當不穩定情況累積時，請從儀表板隔離它們，以免阻擋合併。

此外掛程式亦支援 **壓力測試模式**，會重新執行建置引入的測試案例，並在它們合併前標記任何證實為不穩定的案例。將其加入 `settings.gradle.kts` 中的 `tuist` 擴充功能：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## 套件洞察

Android Gradle Plugin 會在建置輸出中報告產生的 `.aab` 大小。該數字會隨著分支消失，而跨版本比較大小則是一項手動會計工作。Play Console 會報告相同數字，但僅在構件上傳後。

套件洞察會記錄每個 `.aab`（建議）或 `.apk` 的安裝和下載大小，並可在超過每分支閾值時使 PR 檢查失敗。將其加入你的 CI，緊接在建置步驟之後：

```bash
tuist inspect bundle App.aab
```

開啟儀表板上的 **套件洞察 → Android** 以查看趨勢並設定閾值。

## 預覽

Play Console 的內部測試軌道會在每次分享時增加審查和傳播延遲。透過 Slack 或電子郵件傳送原始 `.apk` 更快，但會失去追蹤特定訊息所指涉的建置。

預覽將建置轉換為可分享的連結，接收者只需一個指令即可安裝：

```bash
tuist share App.apk
```

## 邀請團隊加入

快取命中、洞察和壓力測試的效果會隨著連接至專案的人數增加而累積。從儀表板的帳戶設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），讓入職成為一鍵操作，而非每人執行 `tuist auth login`。

對於 CI，請勿使用個人登入。設定範圍限於你專案的 `TUIST_TOKEN`（從儀表板的專案設定建立）。

## 完整外掛程式參考

此處涵蓋的所有內容都是在 Gradle 專案上從 Tuist 獲得價值的最低要求。`tuist` 擴充功能區塊、`stressNewTests` 模式和 CI 驗證的設定選項位於 [安裝 Gradle 外掛程式](https://tuist.dev/en/docs/guides/install-gradle-plugin) 參考文件中。
