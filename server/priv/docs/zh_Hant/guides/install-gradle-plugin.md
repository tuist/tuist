---
{
  "title": "Install the Gradle plugin",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Gradle plugin in your project."
}
---
# 安裝 Gradle 外掛程式 {#install-the-gradle-plugin}

Tuist 提供一個 Gradle 外掛程式，可與您的 Gradle 專案整合，以啟用<.localized_link href="/guides/features/cache/gradle-cache">遠端建置快取</.localized_link>和<.localized_link href="/guides/features/build-insights/gradle">建置洞察</.localized_link>等功能。本指南將逐步引導您安裝並設定該外掛程式。

此外掛程式需要 Gradle 8.12.1 或更新版本。

## 1. 初始化 Tuist {#initialize-tuist}

在您的 Gradle 專案根目錄中執行以下指令：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

該指令將引導您完成身分驗證、建立或選擇 Tuist 專案，以及為您的 Gradle 專案產生設定。

## 2. 套用外掛程式 {#apply-the-plugin}

執行 `tuist init` 後，您需要按照指令輸出的指示，將 Tuist 外掛程式新增至您的 `settings.gradle.kts`：

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. 驗證您的團隊與持續整合環境 {#authenticate}

雖然 `tuist init` 會在本地進行身分驗證，但您的隊友和 <.localized_link href="/guides/integrations/continuous-integration">持續整合</.localized_link> 環境需要分別進行驗證。

每位隊友都應執行以下指令，以便在其機器上存取 Tuist 功能：

```bash
tuist auth login
```

當您使用自託管或本地 Tuist 伺服器時，請傳入與 `tuist.toml` 中設定的相同基礎 URL：

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

保持主機名稱拼寫一致。例如，為 `localhost` 儲存的登入資訊與為 `127.0.0.1` 儲存的登入資訊是分開的。

對於自動化執行器，請遵循 <.localized_link href="/guides/integrations/continuous-integration#authentication">持續整合身分驗證指南</.localized_link> 來為您的環境設定身分驗證。

## 設定快取與隔離專案 {#configuration-cache-and-isolated-projects}

此外掛程式支援 Gradle 的設定快取和 [隔離專案](https://docs.gradle.org/current/userguide/isolated_projects.html)。請將外掛程式保留在 `settings.gradle.kts` 中；您不需要將其單獨套用到每個子專案。

Tuist 不會自動啟用這兩項功能。若要選擇加入，請將以下内容新增至 `gradle.properties`：

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

您的建置腳本和其他外掛程式也必須支援這些功能。Gradle 在儲存設定快取時會報告相容性問題。

## 設定參考 {#configuration-reference}

以下選項可在 `settings.gradle.kts` 中的 `tuist` 擴充區塊中使用：

| 選項 | 類型 | 預設值 | 說明 |
| --- | --- | --- | --- |
| `project` | `String?` | `null`（選用） | 採用 `account/project` 格式的專案識別碼。如果未設定，外掛程式會從 `tuist.toml` 讀取。 |
| `url` | `String?` | `null` | Tuist 伺服器的基礎 URL。如果未設定，則預設為 `"https://tuist.dev"` 或 `tuist.toml` 中定義的值。 |
| `uploadInBackground` | `Boolean?` | `null` | 是否在背景上傳建置和測試洞察。當為 `null`（預設值）時，本機建置的上傳會在背景執行，而持續整合執行器上的上傳則在前台執行。 |
| `stressNewTests.mode` | `String?` | `null` | `"report"` 或 `"enforce"`。重新執行建置新增的測試案例，並標記任何被證明不穩定的案例；請參閱 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">壓力測試新測試</.localized_link>。未設定時為關閉狀態。 |

對於使用 `http://` URL 的本機伺服器，僅在該本機設定中允許不安全協定：

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
> 建議透過專案根目錄中的 `tuist.toml` 檔案來設定 `project`（以及選用的 `url`）。這樣一來，設定就可以在 Tuist 命令列介面和 Gradle 外掛程式之間共用。如有需要，您仍然可以在 `settings.gradle.kts` 中覆寫這些值。

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP 代理伺服器 {#http-proxy}

如果您的網路透過 HTTP 代理伺服器路由傳出流量，請參閱 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理伺服器指南</.localized_link>。

## 下一步 {#next-steps}

一旦外掛程式安裝並設定完成，您就可以啟用：

- <.localized_link href="/guides/features/cache/gradle-cache">遠端建置快取</.localized_link>，以便在您的團隊和持續整合執行器之間共享受建置物件。
- <.localized_link href="/guides/features/build-insights/gradle">建置洞察</.localized_link>，以便在 Tuist 儀表板中追蹤任務耗時和快取行為。
- <.localized_link href="/guides/features/test-insights/gradle">測試洞察</.localized_link>，以便追蹤測試效能並偵測不穩定的測試。
- <.localized_link href="/guides/features/test-insights/flaky-tests">不穩定測試</.localized_link>，以便自動偵測、追蹤並隔離不穩定的測試。
