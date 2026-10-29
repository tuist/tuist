---
{
  "title": "Gradle project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Gradle project to Tuist for a shared remote build cache, build and test insights across CI, bundle-size tracking, and preview links."
}
---
# Gradle 專案 {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

按照此路徑將現有的 Gradle 專案連接至 Tuist。`dev.tuist` Gradle 外掛程式會將 Gradle 的本機建構快取連接到 Tuist 的遠端快取，並將建構和測試資料上傳至儀表板，而無需更改任何 `./gradlew` 指令。

以下每個章節都會先說明目前缺少的功能，然後引導你了解填補該空缺的功能。

## 必要條件

- 一個包含 `settings.gradle.kts`（或 `settings.gradle`）的 Gradle 專案。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

從 Gradle 專案的根目錄執行 `tuist init`。選擇 **整合 Gradle 專案**，然後在瀏覽器中進行驗證，並選擇應該擁有該專案的帳戶。

```bash
tuist init
```

如果你是透過編碼代理程式或腳本來執行此操作，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter 鍵），然後使用非互動式形式：

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist 會在儲存庫根目錄寫入包含專案代號的 `tuist.toml`，並列印出 `plugins { ... }` 區塊。將其貼到 `settings.gradle.kts` 的頂部：

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

使用 `./gradlew help` 進行健全性檢查。Gradle 應該能夠無錯誤地載入。如果找不到外掛程式，請確保該區塊位於 `settings.gradle.kts` 中，而不是 `build.gradle.kts`。

以下所有内容均為可選且獨立。

## 遠端建構快取

Gradle 的本機建構快取會在產生任務輸出的機器上儲存這些輸出。同一分支上的兩位開發人員會命中各自 `~/.gradle` 中的快取，而不會命中對方的快取，且 CI 每次作業都會命中全新的空白快取。

Tuist 遠端快取擴充了 Gradle 已在跨機器使用的相同鍵/值協定。任務的輸出會上傳到首次執行它的機器，並由其他遇到相同輸入的人下載。在 `gradle.properties` 中啟用它：

```properties
org.gradle.caching=true
```

然後在兩個環境中建構：

```bash
./gradlew clean build --build-cache --info
```

可快取的任務在第二次執行時會報告 `FROM-CACHE`。開啟儀表板上的 **快取** 以查看隨時間變化的命中率。

## 建構洞察

Gradle 在建構結束時發出任務計時，並使用 `--profile` 寫入每次建構的 HTML 報告。兩者都不會跨執行彙總。在一系列提交中變慢的任務在任何單次建構的報告中看起來都與以往一樣。

一旦套用 `dev.tuist` 外掛程式，它就會自動將每次建構的任務計時上傳至儀表板。無需額外設定。在下一次 `./gradlew build` 之後，開啟儀表板上的 **建構** 以查看趨勢。

## 測試洞察

Gradle 的測試報告位於每次建構下的 `build/reports/tests/` 中。在十次 CI 運行中間歇性失敗的測試，在任何給定的報告中看起來都像是一個偶爾失敗一次的穩定測試。

測試洞察會記錄每次 `./gradlew test` 運行的每個任務的結果和持續時間，並關聯跨運行的結果。不穩定的測試、緩慢的測試和失敗會顯示在儀表板的 **測試** 標籤頁上。當不穩定情況累積時，請從儀表板隔離它們，以便它們不再阻礙合併。

此外掛程式還支援 **壓力測試模式**，該模式會重新運行建構引入的測試用例，並在它們落地之前標記任何證明不穩定的用例。將其添加到 `settings.gradle.kts` 中的 `tuist` 擴充功能：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## 套件洞察

Android Gradle Plugin 會在建構輸出中報告產生的 `.aab` 的大小。該數字會隨著分支消失，並且跨版本比較大小是一項手動會計工作。Play Console 會報告相同的數字，但僅在工件上傳後才會報告。

套件洞察會記錄每個 `.aab`（推薦）或 `.apk` 的安裝和下載大小，並且當超過每個分支的閾值時可以使 PR 檢查失敗。在建構步驟之後立即將此添加到你的 CI：

```bash
tuist inspect bundle App.aab
```

開啟儀表板上的 **套件洞察 → Android** 以查看趨勢並設定閾值。

## 預覽

Play Console 的內部測試軌道會在每次分享時增加審查和傳播延遲。透過 Slack 或電子郵件發送原始 `.apk` 更快，但會失去追蹤特定訊息指的是哪個建構。

預覽將建構轉換為可分享的連結，接收者可以使用一個指令安裝：

```bash
tuist share App.apk
```

## 帶領團隊一起加入

快取命中、洞察和壓力測試都會隨著連接到專案的人數增加而複合增長。從儀表板的帳戶設定邀請你的隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），以便入職只需點擊一下，而不是每人執行 `tuist auth login`。

對於 CI，請勿使用個人登入。設定範圍限於你專案的 `TUIST_TOKEN`（從儀表板上的專案設定建立）。

## 完整外掛程式參考

此處涵蓋的所有內容都是在 Gradle 專案上從 Tuist 獲得價值的最小要求。`tuist` 擴充功能區塊、`stressNewTests` 模式和 CI 驗證的設定選項位於 [安裝 Gradle 外掛程式](https://tuist.dev/en/docs/guides/install-gradle-plugin) 參考文件中。
