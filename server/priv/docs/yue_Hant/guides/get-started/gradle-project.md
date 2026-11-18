---
{
  "title": "Gradle 專案",
  "titleTemplate": ":title · 入門指南 · 教學文件 · Tuist",
  "description": "將 Gradle 專案連接到 Tuist，以使用共享的遠端建置快取、跨 CI 取得建置與測試分析、追蹤套件大小，並提供預覽連結。"
}
---
# Gradle 項目 {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

按照以下步驟，將現有的 Gradle 項目連接到 Tuist。`dev.tuist` Gradle 外掛程式會將 Gradle 的本機建構快取連接到 Tuist 的遠端快取，並將建構和測試數據上傳到儀表板，而無需更改任何 `./gradlew` 指令。

以下每個章節都會先說明目前缺少的功能，然後引導你使用填補該空缺的功能。

## 必要條件

- 一個包含 `settings.gradle.kts`（或 `settings.gradle`）的 Gradle 項目。
- <.localized_link href="/guides/install-tuist">Tuist 命令列介面</.localized_link>。

## 連接項目

在 Gradle 項目的根目錄中，執行 `tuist init`。選擇 **整合 Gradle 項目**，然後在瀏覽器中進行身份驗證，並選擇應該擁有該項目的帳戶。

```bash
tuist init
```

如果你是从編碼代理程式或腳本驅動此操作，請先執行 `tuist auth login`（瀏覽器流程會等待你按下 Enter 鍵），然後使用非互動式形式：

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist 會在儲存庫根目錄寫入一個包含項目句柄的 `tuist.toml`，並列印一個 `plugins { ... }` 區塊。將其貼上到 `settings.gradle.kts` 的頂部：

<!-- @snippet: ../_gradle-plugin-block -->

使用 `./gradlew help` 進行健全性檢查。Gradle 應該能夠無錯誤地載入。如果找不到外掛程式，請確保該區塊位於 `settings.gradle.kts` 中，而不是 `build.gradle.kts`。

以下所有内容均為可選且獨立。

## 遠端建構快取

Gradle 的本機建構快取會在產生任務輸出的機器上儲存這些輸出。同一分支上的兩位開發人員只會命中各自 `~/.gradle` 中的快取，而不會命中對方的快取；CI 則在每次作業中都會命中一個全新的空快取。

Tuist 遠端快取擴展了 Gradle 已在跨機器使用的相同鍵/值協定。任務的輸出會上傳到首次執行它的機器，並由任何其他遇到相同輸入的人下載。在 `gradle.properties` 中啟用它：

```properties
org.gradle.caching=true
```

然後在兩個環境中建構：

```bash
./gradlew clean build --build-cache --info
```

可快取的任務在第二次運行時會報告 `FROM-CACHE`。在儀表板上打開 **快取** 以查看隨時間變化的命中率。

## 建構洞察

Gradle 在建構結束時發出任務計時，並使用 `--profile` 寫入每個建構的 HTML 報告。兩者都不會跨運行匯總。在一系列提交中變慢的任務，在任何單次建構的報告中看起來都與以往一樣。

一旦應用了 `dev.tuist` 外掛程式，它就會自動將每次建構的任務計時上傳到儀表板。無需額外配置。在下一次 `./gradlew build` 之後，在儀表板上打開 **建構** 以查看趨勢。

## 測試洞察

Gradle 的測試報告位於每個建構下的 `build/reports/tests/` 中。在十次 CI 運行中間歇性失敗的測試，在任何給定的報告中看起來都像是一個偶然失敗一次的穩定測試。

測試洞察會記錄每次 `./gradlew test` 運行的每個任務的結果和持續時間，並關聯跨運行的結果。不穩定測試、緩慢測試和失敗會在儀表板的 **測試** 標籤頁上顯示。當不穩定情況累積時，請從儀表板隔離它們，以便它們不再阻止合併。

該外掛程式還支持 **壓力測試模式**，該模式會重新運行建構引入的測試用例，並在它們合併之前標記任何證明為不穩定的用例。將其添加到 `settings.gradle.kts` 中的 `tuist` 擴展：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## 套件洞察

Android Gradle Plugin 會在建構輸出中報告生成的 `.aab` 的大小。該數字會隨著分支消失，並且比較不同版本之間的大小是一項手動會計工作。Play Console 報告相同的數字，但僅在工件上傳後才報告。

套件洞察會記錄每個 `.aab`（推薦）或 `.apk` 的安裝和下載大小，並且當超過每個分支的閾值時可以使 PR 檢查失敗。將此添加到你的 CI 中，緊接在建構步驟之後：

```bash
tuist inspect bundle App.aab
```

在儀表板上打開 **套件洞察 → Android** 以查看趨勢並配置閾值。

## 預覽

Play Console 的內部測試軌道會在每次分享時增加審查和傳播延遲。通過 Slack 或電子郵件發送原始 `.apk` 更快，但會失去追蹤特定消息指的是哪個建構。

該外掛程式可以直接建構和發布應用程式變體，無需單獨的 CLI 上傳：

```bash
./gradlew :app:tuistShareDebug --track nightly
```

請求 `tuistShare<Variant>` 任務會將該調用選擇加入發布；普通建構從不上傳預覽。有關支持的 APK、簽名和安裝，請參閱 <.localized_link href="/guides/features/previews/gradle">Gradle 預覽</.localized_link>。

## 帶領團隊一起使用

快取命中、洞察和壓力測試都會隨著連接到項目的人數增加而複合增長。從儀表板上的帳戶設置邀請你的隊友加入組織，並設置 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>（Google、Okta、Microsoft），以便入職只需點擊一下，而不是每人執行一次 `tuist auth login`。

對於 CI，不要使用個人登錄。使用你的 CI 提供者的 OIDC 身份進行身份驗證，或在儀表板中使用 **CI** 預設創建帳戶令牌，並將其設置為 `TUIST_TOKEN`。請參閱 <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle 外掛程式身份驗證</.localized_link>。

## 完整外掛程式參考

這裡涵蓋的所有内容都是在 Gradle 項目上從 Tuist 獲取值的最小要求。`tuist` 擴展區塊、`stressNewTests` 模式和 CI 身份驗證的配置選項位於 [安裝 Gradle 外掛程式](https://tuist.dev/en/docs/guides/install-gradle-plugin) 參考中。
