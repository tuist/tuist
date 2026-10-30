---
{
  "title": "安裝 Gradle 外掛程式",
  "titleTemplate": ":title · 指南 · Tuist",
  "description": "了解如何在專案中安裝並設定 Tuist 的 Gradle 外掛程式。"
}
---
# 安裝 Gradle 外掛程式 {#install-the-gradle-plugin}

Tuist 提供一款 Gradle 外掛程式，可與你的 Gradle 專案整合，以啟用<.localized_link href="/guides/features/cache/gradle-cache">遠端建置快取</.localized_link>與<.localized_link href="/guides/features/build-insights/gradle">建置洞察</.localized_link>等功能。本指南將逐步說明如何安裝並設定該外掛程式。

此外掛程式需要 Gradle 8.12.1 或更新版本。

## 1. 初始化 Tuist {#initialize-tuist}

在你的 Gradle 專案根目錄執行以下指令：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

此指令會引導你完成驗證、建立或選擇 Tuist 專案，以及為你的 Gradle 專案產生設定檔。

## 2. 套用外掛程式 {#apply-the-plugin}

執行 `tuist init` 後，請依照指令輸出的指示，將 Tuist 外掛程式加入你的 `settings.gradle.kts`：

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. 為團隊與持續整合進行驗證 {#authenticate}

`tuist init` 僅在本機為你完成驗證，你的隊友與 <.localized_link href="/guides/integrations/continuous-integration">持續整合</.localized_link> 環境仍需分別進行驗證。

每位隊友都應執行以下指令，以便在其機器上使用 Tuist 功能：

```bash
tuist auth login
```

當你使用自託管或本機 Tuist 伺服器時，請傳入與 `tuist.toml` 中設定的相同基礎 URL：

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

請保持主機名稱拼寫一致。例如，為 `localhost` 儲存的登入資訊與為 `127.0.0.1` 儲存的登入資訊是分開的。

對於自動化執行器，請參閱 <.localized_link href="/guides/integrations/continuous-integration#authentication">持續整合驗證指南</.localized_link>，以設定適合你環境的驗證方式。

## 設定快取與隔離專案 {#configuration-cache-and-isolated-projects}

此外掛程式支援 Gradle 的設定快取與 [Isolated Projects](https://docs.gradle.org/current/userguide/isolated_projects.html)。請將外掛程式保留在 `settings.gradle.kts`；你不需要將其分別套用到每個子專案。

Tuist 不會自動啟用任一功能。若要啟用，請將以下內容加入 `gradle.properties`：

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

你的建置腳本與其他外掛程式也必須支援這些功能。Gradle 會在儲存設定快取時回報相容性問題。

## 設定參考 {#configuration-reference}

以下選項可在 `settings.gradle.kts` 中的 `tuist` 擴充區塊中使用：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `project` | `String?` | `null`（選用） | 採用 `account/project` 格式的專案識別碼。若未設定，外掛程式會從 `tuist.toml` 讀取。 |
| `url` | `String?` | `null` | Tuist 伺服器的基礎 URL。若未設定，則預設為 `"https://tuist.dev"` 或 `tuist.toml` 中定義的值。 |
| `uploadInBackground` | `Boolean?` | `null` | 是否在背景上傳建置與測試洞察資料。當為 `null`（預設值）時，本機建置會在背景上傳，而持續整合執行器則會在前台上傳。 |
| `stressNewTests.mode` | `String?` | `null` | `"report"` 或 `"enforce"`。重新執行建置新增的測試案例，並標記任何被證實為不穩定的案例；請參閱 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">壓力測試新測試</.localized_link>。未設定時為關閉狀態。 |

對於使用 `http://` URL 的本機伺服器，僅在該本機設定中允許不安全的通訊協定：

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

請勿為託管或其他 `https://` 伺服器啟用 `allowInsecureProtocol`。

> [!NOTE]
> **Tuist.toml**
>
> 建議透過專案根目錄中的 `tuist.toml` 檔案來設定 `project`（以及選用的 `url`）。如此一來，Tuist 命令列介面與 Gradle 外掛程式即可共用同一份設定。如有需要，你仍可在 `settings.gradle.kts` 中覆寫這些值。

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP 代理伺服器 {#http-proxy}

若你的網路透過 HTTP 代理伺服器路由出站流量，請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理伺服器指南</.localized_link>。

## 後續步驟 {#next-steps}

安裝並設定外掛程式後，你可以啟用：

- <.localized_link href="/guides/features/cache/gradle-cache">遠端建置快取</.localized_link>，以便在團隊與持續整合執行器之間共用建置產物。
- <.localized_link href="/guides/features/build-insights/gradle">建置洞察</.localized_link>，以在 Tuist 儀表板中追蹤任務耗時與快取行為。
- <.localized_link href="/guides/features/test-insights/gradle">測試洞察</.localized_link>，以追蹤測試效能並偵測不穩定測試。
- <.localized_link href="/guides/features/test-insights/flaky-tests">不穩定測試</.localized_link>，以自動偵測、追蹤並隔離不穩定測試。
