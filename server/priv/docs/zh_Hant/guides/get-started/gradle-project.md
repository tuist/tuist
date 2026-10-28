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

依照此路徑將現有的 Gradle 專案指向 Tuist。`dev.tuist` Gradle 外掛程式會將 Gradle 的本機建構快取連接至 Tuist 的遠端快取，並將建構與測試資料上傳至儀表板，且無需變更任何 `./gradlew` 指令。

以下每個章節都會先說明目前缺少的部分，再逐步引導你使用能填補該空缺的功能。

## 必要條件

- 具備 `settings.gradle.kts`（或 `settings.gradle`）的 Gradle 專案。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接專案

在 Gradle 專案的根目錄執行 `tuist init`。選擇 **整合 Gradle 專案**，然後在瀏覽器中進行驗證，並選取應擁有該專案的帳戶。

```bash
tuist init
```

若你是透過編碼代理程式或腳本來執行此操作，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter），接著使用非互動式表單：

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist 會在儲存庫根目錄寫入包含專案代號的 `tuist.toml`，並輸出 `plugins { ... }` 區塊。將其貼到 `settings.gradle.kts` 的頂端：

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

使用 `./gradlew help` 進行健全性檢查。Gradle 應能無錯誤載入。若找不到外掛程式，請確認該區塊位於 `settings.gradle.kts`，而非 `build.gradle.kts`。

以下內容皆為可選且彼此獨立。

## 遠端建構快取

Gradle 的本機建構快取會在產生任務輸出的機器上儲存這些輸出。同一分支上的兩位開發者只會命中各自 `~/.gradle` 中的快取，而不會命中對方的快取；CI 則在每次作業中都會遇到全新且空的快取。

Tuist 遠端快取擴充了 Gradle 已在跨機器使用的相同鍵/值協定。任務的輸出會在上傳至首次執行該任務的機器，並由其他遇到相同輸入的使用者下載。在 `gradle.properties` 中啟用：

```properties
org.gradle.caching=true
```

接著在兩個環境中建構：

```bash
./gradlew clean build --build-cache --info
```

可快取的任務在第二次執行時會回報 `FROM-CACHE`。開啟儀表板上的 **快取** 以查看隨時間變化的命中率。

## 建構洞察

Gradle 在建構結束時會發出任務計時資訊，並透過 `--profile` 撰寫每份建構的 HTML 報告。兩者都不會跨執行彙總。在某一系列提交中逐漸變慢的任務，在任何單一建構報告中看起來都與以往相同。

一旦套用 `dev.tuist` 外掛程式，它就會自動將每次建構的任務計時資訊上傳至儀表板。無需額外設定。在下一次執行 `./gradlew build` 後，開啟儀表板上的 **建構** 以查看趨勢。

## 測試洞察

Gradle 的測試報告位於每次建構下的 `build/reports/tests/`。在十次 CI 執行中間歇性失敗的測試，在任何一份報告中看起來都像是一次偶然失敗的穩定測試。

測試洞察會記錄每次 `./gradlew test` 執行的每個任務結果與持續時間，並跨執行關聯結果。不穩定測試、緩慢測試與失敗會顯示在儀表板的 **測試** 分頁。當不穩定情況累積時，請從儀表板將其隔離，以免阻礙合併。

此外掛程式也支援 **壓力測試模式**，會重新執行建構引入的測試案例，並在它們合併前標記任何證實為不穩定的案例。將其加入 `settings.gradle.kts` 中的 `tuist` 擴充功能：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## 套件洞察

Android Gradle Plugin 會在建構輸出中報告所產生的 `.aab` 大小。該數值會隨著分支消失，而跨版本比較大小則是一項手動核算工作。Play Console 也會報告相同數值，但僅在構件上傳之後。

套件洞察會記錄每個 `.aab`（建議）或 `.apk` 的安裝與下載大小，並在超過每分支門檻時使 PR 檢查失敗。在建構步驟之後立即將此項目加入你的 CI：

```bash
tuist inspect bundle App.aab
```

開啟儀表板上的 **套件洞察 → Android** 以查看趨勢並設定門檻。

## 預覽

Play Console 的內部測試軌道會在每次分享時增加審查與傳播延遲。透過 Slack 或電子郵件傳送原始 `.apk` 雖然較快，但會無法追蹤特定訊息所指涉的是哪一個建構。

預覽會將建構轉換為可分享的連結，接收者只需一個指令即可安裝：

```bash
tuist share App.apk
```

## 邀請團隊成員

快取命中、洞察與壓力測試的效果會隨著連接至專案的人數增加而累積。從儀表板的帳戶設定邀請隊友加入組織，並設定 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），讓入職流程只需點擊一下，而非每人執行一次 `tuist auth login`。

對於 CI，請勿使用個人登入。設定範圍限定於你專案的 `TUIST_TOKEN`（從儀表板的專案設定建立）。

## 完整外掛程式參考

此處涵蓋的所有內容都是在 Gradle 專案上使用 Tuist 獲得價值的最低要求。`tuist` 擴充功能區塊、`stressNewTests` 模式與 CI 驗證的設定選項詳見 [安裝 Gradle 外掛程式](https://tuist.dev/en/docs/guides/install-gradle-plugin) 參考文件。
