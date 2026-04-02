---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# 自行架設安裝{#self-host-installation}

我們為需要對基礎架構擁有更多控制權的組織，提供 Tuist 伺服器的自架設版本。此版本讓您能在自己的基礎架構上架設 Tuist，確保您的資料保持安全與私密。

::: warning LICENSE REQUIRED
<!-- -->
自行架設 Tuist 需具備合法有效的付費授權。Tuist 的本地部署版本僅限於採用 Enterprise 方案的組織使用。若您對此版本有興趣，請聯絡
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

## 發布頻率{#release-cadence}

當可發布的變更推送至主分支時，我們會持續發布 Tuist 的新版本。我們遵循
[語義化版本控制](https://semver.org/)，以確保版本編號的可預測性與相容性。

此主要元件用於標示 Tuist 伺服器中需與本地端使用者協調的重大變更。您不應預期我們會使用此功能；若真有需要，請放心，我們將與您合作，確保過渡過程順利。

## 持續部署{#continuous-deployment}

我們強烈建議您建立一個持續部署管道，讓系統每天自動部署 Tuist 的最新版本。這能確保您隨時都能使用最新的功能、改進項目及安全性更新。

以下是一個 GitHub Actions 工作流程範例，用於每日檢查並部署新版本：

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 3 * * *' # Run daily at 3 AM UTC
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

## 執行環境需求{#runtime-requirements}

本節概述在您的基礎架構上架設 Tuist 伺服器的相關要求。

### 相容性對照表{#compatibility-matrix}

Tuist 伺服器已通過測試，並相容於以下最低版本：

| 元件          | 最低版本   | 注意事項                     |
| ----------- | ------ | ------------------------ |
| PostgreSQL  | 15     | 搭配 TimescaleDB 擴充套件      |
| TimescaleDB | 2.16.1 | 必備的 PostgreSQL 擴充功能（已廢棄） |
| ClickHouse  | 25     | 分析所需                     |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB 目前是 Tuist 伺服器所需的 PostgreSQL 擴充套件，用於時間序列資料的儲存與查詢。然而，**TimescaleDB
已被標記為過時** ，且隨著我們將所有時間序列功能遷移至 ClickHouse，它將在不久的將來從必備依賴項中移除。目前，請確保您的 PostgreSQL
執行個體已安裝並啟用 TimescaleDB。
<!-- -->
:::

### 執行 Docker 虛擬化映像檔{#running-dockervirtualized-images}

我們透過 [GitHub 的 Container
Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)，以
[Docker](https://www.docker.com/) 映像檔的形式發佈此伺服器。

要執行此程序，您的基礎架構必須支援執行 Docker 映像檔。請注意，由於 Docker
已成為生產環境中分發和執行軟體的標準容器，因此大多數基礎架構供應商皆支援此功能。

### Postgres 資料庫{#postgres-database}

除了執行 Docker 映像檔外，您還需要一個安裝了 [TimescaleDB 擴充套件](https://www.timescale.com/) 的
[Postgres 資料庫](https://www.postgresql.org/)，用以儲存關聯式資料與時間序列資料。大多數基礎設施供應商皆在其服務中提供
Postgres 資料庫（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 與 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)）。

**需安裝 TimescaleDB 擴充套件：** Tuist 需安裝 TimescaleDB
擴充套件，以實現高效的時間序列資料儲存與查詢。此擴充套件用於命令事件、分析及其他基於時間的功能。在執行 Tuist 之前，請確保您的 PostgreSQL
執行個體已安裝並啟用 TimescaleDB。

::: info MIGRATIONS
<!-- -->
Docker 映像的 entrypoint 會在啟動服務前，自動執行任何待處理的資料庫結構遷移。若因缺少 TimescaleDB
擴充套件而導致遷移失敗，您需先在資料庫中安裝該擴充套件。
<!-- -->
:::

### ClickHouse 資料庫{#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 來儲存和查詢大量分析資料。ClickHouse 是**所必需的**
，用於實現諸如建立洞察等功能，並將在我們逐步淘汰 TimescaleDB 後，成為主要的時間序列資料庫。您可以選擇自行架設
ClickHouse，或使用他們的託管服務。

::: info MIGRATIONS
<!-- -->
Docker 映像的 entrypoint 會在啟動服務前，自動執行任何待處理的 ClickHouse 資料結構遷移。
<!-- -->
:::

### 儲存{#storage}

您還需要一個用於儲存檔案（例如框架和函式庫二進位檔）的解決方案。目前我們支援任何符合 S3 規範的儲存服務。

::: tip OPTIMIZED CACHING
<!-- -->
若您的主要目的是自建儲存二進位檔的空間並降低快取延遲，或許無需自行架設整個伺服器。您可以自行架設快取節點，並將其連接到託管版的 Tuist
伺服器或您自行架設的伺服器。

請參閱 <LocalizedLink href="/guides/cache/self-host">快取自主架設指南</LocalizedLink>。
<!-- -->
:::

## 組態{#configuration}

本服務的設定是透過環境變數在執行時進行的。鑑於這些變數的敏感性質，我們建議將其加密並儲存於安全的密碼管理解決方案中。請放心，Tuist
會以極其謹慎的態度處理這些變數，確保它們絕不會出現在日誌中。

::: info LAUNCH CHECKS
<!-- -->
系統會在啟動時驗證必要的變數。若任何變數缺失，程式將無法啟動，並會顯示錯誤訊息說明缺失的變數。
<!-- -->
:::

### 授權設定{#license-configuration}

身為本地部署使用者，您將收到一組授權金鑰，需將其設定為環境變數。此金鑰用於驗證授權，並確保服務的運作符合協議條款。

| 環境變數                               | 說明                                                                                                        | 必填  | 預設  | 範例                                        |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------- | --- | --- | ----------------------------------------- |
| `TUIST_LICENSE`                    | 簽署服務水準協議後提供的授權                                                                                            | 是*  |     | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **`TUIST_LICENSE` 的特殊替代方案** 。此為 Base64 編碼的公開憑證，用於在伺服器無法連線至外部服務的物理隔離環境中進行離線授權驗證。僅在無法使用`TUIST_LICENSE` 時才使用 | 是*  |     | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* 必須提供`TUIST_LICENSE` 或`TUIST_LICENSE_CERTIFICATE_BASE64`
其中之一，但不可同時提供兩者。標準部署請使用`TUIST_LICENSE` 。

::: warning EXPIRATION DATE
<!-- -->
授權證有有效期限。若授權證在 30 天內即將過期，使用者在使用與伺服器互動的 Tuist 指令時，將會收到警告。若您有意續訂授權證，請聯絡
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

### 基礎環境設定{#base-environment-configuration}

| 環境變數                                  | 說明                                                                           | 必填  | 預設                                 | 範例                                                                 |                                                                                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------- | --- | ---------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | 從網際網路存取該實例的基礎 URL                                                            | 是   |                                    | https://tuist.dev                                                  |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | 用於加密資訊（例如 Cookie 中的會話）的金鑰                                                    | 是   |                                    |                                                                    | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | 使用 Pepper 生成雜湊密碼                                                             | 否   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | 生成隨機代幣的密鑰                                                                    | 否   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | 用於敏感資料 AES-GCM 加密的 32 位元組金鑰                                                  | 否   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | 當執行`1` 時，系統會將應用程式設定為使用 IPv6 位址                                               | 否   | `0`                                | `1`                                                                |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | 應用程式應使用的日誌等級                                                                 | 否   | `資訊`                               | [日誌等級](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | 您的 GitHub 應用程式名稱的 URL 版本                                                     | 否   |                                    | `my-app`                                                           |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用於 GitHub 應用程式以解鎖額外功能（例如發佈自動 PR 評論）的 Base64 編碼私密金鑰                           | 否   | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                    |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | 此私密金鑰用於 GitHub 應用程式，以解鎖額外功能，例如發佈自動 PR 評論。**我們建議改用 base64 編碼版本，以避免特殊字元引發的問題** | 否   | `-----BEGIN RSA...`                |                                                                    |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | 一個以逗號分隔的用戶識別碼清單，這些用戶具有存取操作 URL 的權限                                           | 否   |                                    | `user1,user2`                                                      |                                                                                                                                    |
| `TUIST_WEB`                           | 啟用網頁伺服器端點                                                                    | 否   | `1`                                | `1` 或`0`                                                           |                                                                                                                                    |

### 資料庫設定{#database-configuration}

以下環境變數用於設定資料庫連線：

| 環境變數                                 | 說明                                                                                                                        | 必填  | 預設        | 範例                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | 存取 Postgres 資料庫的 URL。請注意，該 URL 應包含驗證資訊                                                                                    | 是   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | 存取 ClickHouse 資料庫的 URL。請注意，該 URL 應包含驗證資訊                                                                                  | 否   |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | 若為 true，則使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連線至資料庫                                          | 否   | `1`       | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | 連接池中應保留的開放連接數                                                                                                             | 否   | `10`      | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | 檢查從連接池中借出的所有連接是否超過佇列間隔的時間間隔（以毫秒為單位）[(更多資訊)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否   | `300`     | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | 該池用於判斷是否應開始捨棄新連線的佇列閾值時間（以毫秒為單位）[(更多資訊)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)     | 否   | `1000`    | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 緩衝區刷新之間的間隔時間（以毫秒為單位）                                                                                           | 否   | `5000`    | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | 在強制刷新之前，ClickHouse 緩衝區的最大大小（以位元組為單位）                                                                                      | 否   | `1000000` | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | 要執行的 ClickHouse 緩衝區進程數量                                                                                                   | 否   | `5`       | `5`                                                                    |

### 驗證環境設定{#authentication-environment-configuration}

我們透過 [身分識別供應商 (IdP)](https://en.wikipedia.org/wiki/Identity_provider)
提供驗證功能。若要使用此功能，請確保伺服器環境中已設定所選供應商所需的所有環境變數。**若缺少變數** ，Tuist 將跳過該供應商。

#### GitHub{#github}

我們建議使用 [GitHub
App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)
進行驗證，但您也可以使用 [OAuth
App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。請務必在伺服器環境中包含
GitHub 指定的所有必要環境變數。若缺少變數，將導致 Tuist 無法完成 GitHub 驗證。要正確設定 GitHub App：
- 在 GitHub 應用程式的「一般設定」中：
    - 複製`中的 Client ID` ，並將其設定為`TUIST_GITHUB_APP_CLIENT_ID`
    - 建立並複製新的`客戶端密鑰` ，並將其設定為`TUIST_GITHUB_APP_CLIENT_SECRET`
    - 將`的回呼網址` 設定為`http://YOUR_APP_URL/users/auth/github/callback`
      。`YOUR_APP_URL` 也可以是您伺服器的 IP 位址。
- 需要以下權限：
  - 儲存庫：
    - 拉取請求：讀取與寫入
  - 帳戶：
    - 電子郵件地址：唯讀

在`權限與事件` 的`帳戶權限` 區段中，將`電子郵件地址` 權限設定為`唯讀` 。

接著，您需要在 Tuist 伺服器執行的環境中設定以下環境變數：

| 環境變數                             | 說明                 | 必填  | 預設  | 範例                                         |
| -------------------------------- | ------------------ | --- | --- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | GitHub 應用程式的客戶端 ID | 是   |     | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 該應用程式的客戶端密鑰        | 是   |     | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google{#google}

您可以透過 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 設定
Google 驗證。為此，您需要建立一個 OAuth 客戶端 ID 類型的憑證。建立憑證時，請選擇「Web
Application」作為應用程式類型，將其命名為`Tuist` ，並將重定向 URI
設定為`{base_url}/users/auth/google/callback` ，其中`base_url` 是您託管服務的運作網址。
建立應用程式後，請複製客戶端 ID 和密鑰，並分別將其設定為環境變數：`（GOOGLE_CLIENT_ID）`
以及`（GOOGLE_CLIENT_SECRET）` 。

::: info CONSENT SCREEN SCOPES
<!-- -->
您可能需要建立一個同意畫面。建立時，請務必新增`userinfo.email` 以及`openid` 這些權限範圍，並將應用程式標記為內部使用。
<!-- -->
:::

#### Okta{#okta}

您可以透過 [OAuth 2.0](https://oauth.net/2/) 協定啟用 Okta 驗證。您必須依照
<LocalizedLink href="/guides/integrations/sso#okta">這些說明</LocalizedLink> 在 Okta
上
[建立應用程式](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在設定 Okta 應用程式時取得客戶端 ID 和密鑰後，您需要設定以下環境變數：

| 環境變數                         | 說明                                | 必填  | 預設  | 範例  |
| ---------------------------- | --------------------------------- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID`     | 用於對 Okta 進行驗證的客戶端 ID。此數字應為您的組織 ID | 是   |     |     |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用於對 Okta 進行驗證的客戶端密鑰               | 是   |     |     |

數字`1` 需替換為您的組織 ID。此值通常為 1，但請務必查閱您的資料庫。

### 儲存環境設定{#storage-environment-configuration}

Tuist 需要儲存空間來存放透過 API 上傳的工件。為確保 Tuist 能有效運作，配置其中一種受支援的儲存解決方案** 是**不可或缺的。

#### 符合 S3 標準的儲存空間{#s3compliant-storages}

您可以使用任何符合 S3 標準的儲存服務供應商來儲存建置產出。以下環境變數是為了驗證身分並設定與儲存服務供應商的整合所必需的：

| 環境變數                                                  | 說明                                                       | 必填  | 預設       | 範例                                                            |
| ----------------------------------------------------- | -------------------------------------------------------- | --- | -------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` 或`AWS_ACCESS_KEY_ID`         | 用於向儲存供應商進行驗證的存取金鑰 ID                                     | 是   |          | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` 或`AWS_SECRET_ACCESS_KEY` | 用於向儲存供應商進行驗證的秘密存取金鑰                                      | 是   |          | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` 或`AWS_REGION`                       | 儲存桶所在的區域                                                 | 否   | `auto`   | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` 或`AWS_ENDPOINT`                   | 儲存提供者的終端點                                                | 是   |          | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                | 用於儲存工件的儲存桶名稱                                             | 是   |          | `tuist-artifacts`                                             |
| `TUIST_S3_CA_CERT_PEM`                                | 用於驗證 S3 HTTPS 連線的 PEM 格式 CA 憑證。適用於使用自簽名憑證或內部憑證授權機構的隔離環境。 | 否   | 系統 CA 套件 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                            | 建立與儲存供應商連線的超時設定（單位為毫秒）                                   | 否   | `3000`   | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                            | 從儲存供應商接收資料的超時設定（單位為毫秒）                                   | 否   | `5000`   | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                               | 儲存供應商連線池的超時設定（單位為毫秒）。若要取消超時設定，請使用`infinity`              | 否   | `5000`   | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                         | 連接池中連接的最大閒置時間（以毫秒為單位）。若要讓連接永久保持活躍，請使用 ``infinity``       | 否   | `無限`     | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                  | 每個連接池的最大連接數                                              | 否   | `500`    | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                 | 要使用的連線池數量                                                | 否   | 系統排程器數量  | `4`                                                           |
| `TUIST_S3_PROTOCOL`                                   | 連線至儲存供應商時應使用的通訊協定 (`http1` 或`http2`)                     | 否   | `http1`  | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                               | URL 是否應以儲存桶名稱作為子網域（虛擬主機）來建構                              | 否   | `false`  | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
若您的儲存服務供應商為 AWS，且希望使用 web identity token
進行驗證，您可以將環境變數`TUIST_S3_AUTHENTICATION_METHOD`
設定為`aws_web_identity_token_from_env_vars` ，Tuist 將透過標準的 AWS 環境變數使用該方法。
<!-- -->
:::

#### Google Cloud Storage{#google-cloud-storage}
對於 Google Cloud Storage，請參照
[此文件](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)
取得`的 AWS_ACCESS_KEY_ID` 以及`的 AWS_SECRET_ACCESS_KEY` 配對。`的 AWS_ENDPOINT`
應設定為`https://storage.googleapis.com` 。其他環境變數與任何其他符合 S3 標準的儲存空間相同。

### 電子郵件設定{#email-configuration}

Tuist 需要電子郵件功能以進行使用者驗證及交易通知（例如：密碼重設、帳戶通知）。目前，**僅支援 Mailgun** 作為電子郵件服務提供商。

| 環境變數                             | 說明                                            | 必填  | 預設                                   | 範例                     |
| -------------------------------- | --------------------------------------------- | --- | ------------------------------------ | ---------------------- |
| `TUIST_MAILGUN_API_KEY`          | 用於 Mailgun 驗證的 API 金鑰                         | 是*  |                                      | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN`           | 發送電子郵件的網域                                     | 是*  |                                      | `mg.tuist.io`          |
| `TUIST_MAILING_FROM_ADDRESS`     | 將顯示於「寄件者」欄位的電子郵件地址                            | 是*  |                                      | `noreply@tuist.io`     |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 用戶回覆的可選回覆地址                                   | 否   |                                      | `support@tuist.dev`    |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | 跳過新用戶註冊時的電子郵件確認步驟。啟用此功能後，用戶將自動完成確認，並可在註冊後立即登入 | 否   | `true` （若未設定電子郵件），`false` （若已設定電子郵件） | `true`,`false`,`1`,`0` |

\* 電子郵件設定變數僅在您需要發送電子郵件時才需設定。若未設定，系統將自動跳過電子郵件確認步驟

::: info SMTP SUPPORT
<!-- -->
目前尚未提供通用 SMTP 支援。若您需要針對本地部署的 SMTP 支援，請聯絡
[contact@tuist.dev](mailto:contact@tuist.dev) 討論您的需求。
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
對於無法連網或未設定電子郵件服務提供者的本地部署安裝，預設會自動跳過電子郵件確認步驟。使用者註冊後即可立即登入。若您已設定電子郵件但仍希望跳過確認步驟，請設定`TUIST_SKIP_EMAIL_CONFIRMATION=true`
。若需在設定電子郵件時強制進行確認，請設定`TUIST_SKIP_EMAIL_CONFIRMATION=false` 。
<!-- -->
:::

### Git 平台設定{#git-platform-configuration}

Tuist 可 <LocalizedLink href="/guides/server/authentication">與 Git
平台</LocalizedLink> 整合，提供額外功能，例如在您的拉取請求中自動發表評論。

#### GitHub{#platform-github}

您需要 [建立一個 GitHub
應用程式](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。除非您建立的是
OAuth GitHub 應用程式，否則可以重複使用先前建立的應用程式進行驗證。在`權限與事件` 的`儲存庫權限` 區段中，您還需將`拉取請求`
權限設定為`讀取與寫入` 。

除了`TUIST_GITHUB_APP_CLIENT_ID` 以及`TUIST_GITHUB_APP_CLIENT_SECRET`
之外，您還需要設定以下環境變數：

| 環境變數                           | 說明               | 必填  | 預設  | 範例                                   |
| ------------------------------ | ---------------- | --- | --- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub 應用程式的私密金鑰 | 是   |     | `-----BEGIN RSA PRIVATE KEY-----...` |

## 本地測試{#testing-locally}

我們提供一套完整的 Docker Compose 配置，其中包含所有必要依賴項，讓您能在部署至基礎架構之前，於本地端測試 Tuist 伺服器：

- PostgreSQL 15 搭配 TimescaleDB 2.16 擴充套件（已廢棄）
- ClickHouse 25 分析版
- ClickHouse Keeper 負責協調
- 適用於 S3 相容儲存的 MinIO
- Redis 用於跨部署的持久化 KV 儲存（可選）
- pgweb 用於資料庫管理

::: danger LICENSE REQUIRED
<!-- -->
根據法規要求，執行 Tuist 伺服器（包括本地開發實例）時，必須設定有效的`TUIST_LICENSE` 環境變數。若您需要授權，請聯絡
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

**快速入門：**

1. 下載設定檔：
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 設定環境變數：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE and authentication credentials
   ```

3. 啟動所有服務：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

4. 請透過 http://localhost:8080 存取伺服器

**服務端點：**
- Tuist 伺服器：http://localhost:8080
- MinIO 控制台：http://localhost:9003（憑證：`tuist` /`tuist_dev_password` ）
- MinIO API：http://localhost:9002
- pgweb (PostgreSQL 使用者介面)：http://localhost:8081
- Prometheus Metrics：http://localhost:9091/metrics
- ClickHouse HTTP：http://localhost:8124

**常用指令：**

檢查服務狀態：
```bash
docker compose ps
# or: podman compose ps
```

檢視日誌：
```bash
docker compose logs -f tuist
```

停止服務：
```bash
docker compose down
```

重置所有設定（刪除所有資料）：
```bash
docker compose down -v
```

**設定檔：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整的 Docker
  Compose 配置
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse
  設定檔
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - ClickHouse Keeper 設定檔
- [.env.example](/server/self-host/.env.example) - 環境變數範例檔案

## 部署{#deployment}

官方 Tuist Docker 映像檔可於以下位置取得：
```
ghcr.io/tuist/tuist
```

### 拉取 Docker 映像檔{#pulling-the-docker-image}

您可以執行以下指令來取得該圖片：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

或拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 映像檔{#deploying-the-docker-image}

Docker 映像的部署流程會因您選擇的雲端服務供應商及貴組織的持續部署方法而有所不同。由於大多數雲端解決方案和工具（例如
[Kubernetes](https://kubernetes.io/)）皆以 Docker 映像作為基本單位，本節中的範例應能與您的現有設定相容。

::: warning
<!-- -->
若您的部署管道需要驗證伺服器是否正常運作，您可以向`/ready` 發送`GET` HTTP 請求，並驗證回應中是否包含`200` 狀態碼。
<!-- -->
:::

#### Fly{#fly}

若要在 [Fly](https://fly.io/) 上部署應用程式，您需要一份`fly.toml` 配置檔。建議您在持續部署 (CD)
管道中動態生成此檔案。以下提供一個參考範例供您使用：

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

接著，您可以執行`fly launch --local-only --no-deploy` 來啟動應用程式。在後續部署時，請勿執行`fly launch
--local-only` ，而是需執行`fly deploy --local-only` 。Fly.io 不允許拉取私有 Docker
映像檔，因此我們需要使用`--local-only` 這個參數。


## Prometheus 指標{#prometheus-metrics}

Tuist 透過`/metrics` 公開 Prometheus 指標，協助您監控自建的實例。這些指標包含：

### Finch HTTP 客戶端指標{#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作為其 HTTP 客戶端，並提供有關 HTTP
請求的詳細指標：

#### 請求指標
- `tuist_prom_ex_finch_request_count_total` - Finch 請求總數 (計數器)
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 請求的持續時間（直方圖）
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
  - 時間區間：10 毫秒、50 毫秒、100 毫秒、250 毫秒、500 毫秒、1 秒、2.5 秒、5 秒、10 秒
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 請求例外總數（計數器）
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`kind`,`reason`

#### 連線池佇列指標
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在連線池佇列中等待的時間 (直方圖)
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 時間區間：1 毫秒、5 毫秒、10 毫秒、25 毫秒、50 毫秒、100 毫秒、250 毫秒、500 毫秒、1 秒
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 連線在被使用前處於閒置狀態的時間（直方圖）
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 區間：10 毫秒、50 毫秒、100 毫秒、250 毫秒、500 毫秒、1 秒、5 秒、10 秒
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 佇列例外狀況的總數（計數器）
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`kind`,`reason`

#### 連線指標
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立連線所花費的時間（直方圖）
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`error`
  - 時間區間：10 毫秒、50 毫秒、100 毫秒、250 毫秒、500 毫秒、1 秒、2.5 秒、5 秒
- `tuist_prom_ex_finch_connect_count_total` - 連線嘗試總數 (計數器)
  - 標籤：`finch_name`,`scheme`,`host`,`port`

#### 傳送指標
- `tuist_prom_ex_finch_send_duration_milliseconds` - 傳送請求所花費的時間（直方圖）
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 時間區間：1 毫秒、5 毫秒、10 毫秒、25 毫秒、50 毫秒、100 毫秒、250 毫秒、500 毫秒、1 秒
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 發送前連線處於閒置狀態的時間（直方圖）
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 區間：1 毫秒、5 毫秒、10 毫秒、25 毫秒、50 毫秒、100 毫秒、250 毫秒、500 毫秒

所有直方圖指標均提供`_bucket` 、`_sum` 以及`_count` 等變體，以供進行詳細分析。

### 其他指標

除了 Finch 指標外，Tuist 還提供以下指標：
- BEAM 虛擬機性能
- 自訂業務邏輯指標（儲存空間、帳戶、專案等）
- 資料庫效能（使用 Tuist 託管基礎架構時）

## 操作{#operations}

Tuist 提供了一組位於`/ops/` 的工具，您可以使用這些工具來管理您的實例。

::: warning Authorization
<!-- -->
僅有其使用者名稱列於`TUIST_OPS_USER_HANDLES` 環境變數中的人員，方可存取`/ops/` 端點。
<!-- -->
:::

- **錯誤 (`/ops/errors`)：**
  您可在此查看應用程式中發生的意外錯誤。這對於除錯及了解問題根源非常有用，若您遇到問題，我們可能會請您與我們分享此資訊。
- **儀表板 (`/ops/dashboard`)：**
  您可查看此儀表板，以了解應用程式的效能與運作狀態（例如：記憶體使用量、執行中的程序、請求數量）。此儀表板對於判斷您使用的硬體是否足以應付負載非常有用。
