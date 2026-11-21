---
{
  "title": "安裝 Gradle 外掛程式",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "了解如何在專案中安裝與設定 Tuist 的 Gradle 外掛程式。"
}
---
# 安裝 Gradle 外掛程式 {#install-the-gradle-plugin}

Tuist 提供一個 Gradle 外掛程式，可與你的 Gradle 專案整合，以啟用<.localized_link href="/guides/features/cache/gradle-cache">遠端建置快取</.localized_link>和<.localized_link href="/guides/features/build-insights/gradle">建置洞察</.localized_link>等功能。本指南將逐步說明如何安裝與設定此外掛程式。

此外掛程式需要 Gradle 8.12.1 或更新版本。

## 1. 初始化 Tuist {#initialize-tuist}

在你的 Gradle 專案根目錄中執行以下指令：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

此指令將引導你完成驗證、建立或選擇 Tuist 專案，並為你的 Gradle 專案產生設定。

## 2. 套用外掛程式 {#apply-the-plugin}

執行 `tuist init` 後，你需要依照指令輸出的指示，將 Tuist 外掛程式加入至 `settings.gradle.kts`：

<!-- @snippet: ./_gradle-plugin-block -->

## 3. 驗證你的團隊與持續整合環境 {#authenticate}

雖然 `tuist init` 會在本地進行驗證，但你的隊友與 <.localized_link href="/guides/integrations/continuous-integration">持續整合</.localized_link> 環境仍需分別進行驗證。

每位隊友都應執行以下指令，以便在其機器上存取 Tuist 功能：

```bash
tuist auth login
```

當你使用自架或本地 Tuist 伺服器時，請傳入在 `tuist.toml` 中設定的相同基礎 URL：

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

請保持主機名稱拼寫一致。例如，為 `localhost` 儲存的登入資訊與為 `127.0.0.1` 儲存的登入資訊是分開的。

對於自動化執行器，請參閱 <.localized_link href="/guides/server/authentication#continuous-integration">持續整合驗證指南</.localized_link> 以設定適合你環境的驗證。

## 設定快取與隔離專案 {#configuration-cache-and-isolated-projects}

此外掛程式支援 Gradle 的設定快取與 [隔離專案](https://docs.gradle.org/current/userguide/isolated_projects.html)。請將外掛程式保留在 `settings.gradle.kts` 中；你不需要將其分別套用到每個子專案。

Tuist 不會自動啟用任一功能。若要選用，請將以下內容加入至 `gradle.properties`：

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

你的建置腳本與其他外掛程式也必須支援這些功能。Gradle 會在儲存設定快取時回報相容性問題。

## 發布預覽 {#publish-previews}

對於 Android 應用程式模組，此外掛程式會註冊 `tuistShare<Variant>` 工作：

```bash
./gradlew :app:tuistShareDebug --track nightly
```

此工作會建置並驗證單一已簽署的 APK，然後使用你現有的 Tuist 驗證進行發布。叫用此工作即表示選用：一般的 `assemble`、`build` 與測試工作不會發布預覽。無需執行 CLI 上傳步驟。如需了解資格條件、快取重放與失敗行為，請參閱 <.localized_link href="/guides/features/previews/gradle">Gradle 預覽</.localized_link>。

## 設定參考 {#configuration-reference}

以下選項可在 `settings.gradle.kts` 中的 `tuist` 擴充區塊中使用：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `project` | `String?` | `null`（選填） | 採用 `account/project` 格式的專案識別碼。若未設定，外掛程式會從 `tuist.toml` 讀取。 |
| `url` | `String?` | `null` | Tuist 伺服器的基礎 URL。若未設定，則預設為 `"https://tuist.dev"` 或 `tuist.toml` 中定義的值。 |
| `uploadInBackground` | `Boolean?` | `null` | 是否在背景上傳建置與測試洞察。當為 `null`（預設值）時，本地建置會在背景執行上傳，而持續整合執行器則在前台執行。 |
| `stressNewTests.mode` | `String?` | `null` | `"report"` 或 `"enforce"`。重新執行建置新增的測試案例，並標記任何被證明為不穩定的案例；請參閱 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">壓力測試新測試</.localized_link>。若未設定則關閉。 |
| `coverage.enabled` | `Boolean?` | `null` | 使用 JaCoCo 測量測試涵蓋率，並隨每次測試執行上傳。若未設定則關閉。`TUIST_TEST_COVERAGE` 環境變數會覆寫此設定；請參閱 <.localized_link href="/guides/features/test-code-coverage/gradle">Gradle 程式碼涵蓋率</.localized_link>。 |

對於使用 `http://` URL 的本地伺服器，僅在該本地設定中允許不安全協定：

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

不要為託管或其他 `https://` 伺服器啟用 `allowInsecureProtocol`。

> [!NOTE]
> **Tuist.toml**
>
> 建議透過專案根目錄中的 `tuist.toml` 檔案來設定 `project`（以及選填的 `url`）。如此一來，Tuist 命令列介面與 Gradle 外掛程式即可共用此設定。如有需要，你仍可在 `settings.gradle.kts` 中覆寫這些值。

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP 代理伺服器 {#http-proxy}

如果你的網路透過 HTTP 代理伺服器路由出站流量，請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理伺服器指南</.localized_link>。

## 後續步驟 {#next-steps}

安裝並設定外掛程式後，你可以啟用：

- <.localized_link href="/guides/features/cache/gradle-cache">遠端建置快取</.localized_link>，以便在團隊與持續整合執行器之間共用建置產物。
- <.localized_link href="/guides/features/build-insights/gradle">建置洞察</.localized_link>，以在 Tuist 儀表板中追蹤工作耗時與快取行為。
- <.localized_link href="/guides/features/test-insights/gradle">測試洞察</.localized_link>，以追蹤測試效能並偵測不穩定測試。
- <.localized_link href="/guides/features/test-insights/flaky-tests">不穩定測試</.localized_link>，以自動偵測、追蹤並隔離不穩定測試。
- <.localized_link href="/guides/features/test-code-coverage/gradle">程式碼涵蓋率</.localized_link>，以依提交、專案與檔案追蹤測試涵蓋率。
