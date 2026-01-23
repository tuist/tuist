---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# 自行架設安裝{#self-host-installation}

我們為需要更全面基礎設施控制權的組織提供 Tuist 伺服器的自託管版本。此版本允許您在自有基礎設施上託管 Tuist，確保您的資料安全且私密無虞。

::: warning LICENSE REQUIRED
<!-- -->
自行架設 Tuist 需具備合法有效的付費授權。Tuist 內部部署版本僅限採用企業方案的組織使用。若您對此版本感興趣，請聯繫
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

## 發布節奏{#release-cadence}

我們會持續在主分支出現可發布的變更時，釋出 Tuist 的新版本。我們遵循 [語義化版本控制規範](https://semver.org/)
以確保版本編號的可預測性與相容性。

主要組件用於標記 Tuist 伺服器中需與本地端使用者協調的重大變更。請勿預期我們會使用此功能，若確有需要，請放心我們將與您協力確保平穩過渡。

## 持續部署{#continuous-deployment}

我們強烈建議建立持續部署管道，每日自動部署 Tuist 最新版本。此舉可確保您隨時享有最新功能、改進項目及安全更新。

以下是一個每日檢查並部署新版本的 GitHub Actions 工作流程範例：

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

## 執行時需求{#runtime-requirements}

本節概述在您的基礎架構上託管 Tuist 伺服器的相關要求。

### 相容性對照表{#compatibility-matrix}

Tuist 伺服器已通過測試，相容於下列最低版本：

| 元件          | 最低版本   | 注意事項                    |
| ----------- | ------ | ----------------------- |
| PostgreSQL  | 15     | 使用 TimescaleDB 擴充套件     |
| TimescaleDB | 2.16.1 | 所需 PostgreSQL 擴充套件（已棄用） |
| ClickHouse  | 25     | 分析所需                    |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB 目前是 Tuist 伺服器所需的 PostgreSQL 擴充套件，用於時間序列資料儲存與查詢。然而，**TimescaleDB
已被廢棄** ，隨著我們將所有時間序列功能遷移至 ClickHouse，它將在不久的將來不再是必要依賴項。目前請確保您的 PostgreSQL 實例已安裝並啟用
TimescaleDB。
<!-- -->
:::

### 執行 Docker 虛擬化映像檔{#running-dockervirtualized-images}

我們透過[GitHub的容器註冊表](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)以[Docker](https://www.docker.com/)映像檔形式發佈此伺服器。

執行此程序時，您的基礎架構必須支援運行 Docker 映像檔。請注意，由於 Docker
已成為生產環境中分發和運行軟體的標準容器，多數基礎架構供應商皆提供此支援。

### Postgres 資料庫{#postgres-database}

除了執行 Docker 映像檔外，您還需要一個配備 [TimescaleDB 擴充套件](https://www.timescale.com/) 的
[Postgres 資料庫](https://www.postgresql.org/) 來儲存關聯式與時間序列資料。多數基礎架構供應商皆提供內建
Postgres 資料庫服務（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 與 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)）。

**TimescaleDB 擴充套件需求：** Tuist 需安裝 TimescaleDB
擴充套件以實現高效的時間序列資料儲存與查詢。此擴充套件用於指令事件、分析及其他時間相關功能。執行 Tuist 前，請確認您的 PostgreSQL
實例已安裝並啟用 TimescaleDB。

::: info MIGRATIONS
<!-- -->
Docker 映像的入口點會在啟動服務前自動執行所有待處理的架構遷移。若因缺少 TimescaleDB 擴充套件導致遷移失敗，您需先在資料庫中安裝該擴充套件。
<!-- -->
:::

### ClickHouse 資料庫{#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 儲存與查詢大量分析數據。ClickHouse 是**所需的**
功能（如建置洞察），並將成為我們逐步淘汰 TimescaleDB 後的主要時間序列資料庫。您可選擇自行架設 ClickHouse 或使用其託管服務。

::: info MIGRATIONS
<!-- -->
Docker 映像的入口點會在啟動服務前，自動執行任何待處理的 ClickHouse 資料結構遷移。
<!-- -->
:::

### 儲存{#storage}

您還需要解決方案來儲存檔案（例如框架與函式庫的二進位檔）。目前我們支援任何符合 S3 標準的儲存方案。

::: tip OPTIMIZED CACHING
<!-- -->
若您的主要目標是建立專屬儲存二進位檔的儲存桶並降低快取延遲，則無需自行架設完整伺服器。您可自行架設快取節點，並將其連接至託管的 Tuist
伺服器或您自行架設的伺服器。

參閱 <LocalizedLink href="/guides/cache/self-host">快取自託管指南</LocalizedLink>。
<!-- -->
:::

## 組態{#configuration}

服務設定於執行階段透過環境變數完成。鑑於這些變數的敏感性質，建議採用加密方式並儲存於安全的密碼管理解決方案中。請放心，Tuist
會以最高標準處理這些變數，確保它們絕不會出現在日誌中。

::: info LAUNCH CHECKS
<!-- -->
必要變數將於啟動時進行驗證。若任何變數缺失，啟動程序將失敗，錯誤訊息將詳細列出缺失的變數。
<!-- -->
:::

### 授權設定{#license-configuration}

作為本地部署使用者，您將收到需設定為環境變數的授權金鑰。此金鑰用於驗證授權資格，確保服務符合協議條款運行。

| 環境變數                               | 說明                                                                                                  | 必填  | 預設  | 範例                                        |
| ---------------------------------- | --------------------------------------------------------------------------------------------------- | --- | --- | ----------------------------------------- |
| `TUIST_LICENSE`                    | 簽署服務等級協議後提供的授權條款                                                                                    | 是*  |     | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **`TUIST_LICENSE` 的特殊替代方案** 。此為 Base64 編碼的公開憑證，適用於伺服器無法連線外部服務的離線環境進行授權驗證。僅在無法使用`TUIST_LICENSE` 時啟用。 | 是*  |     | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* 必須提供以下任一選項：`TUIST_LICENSE` 或`TUIST_LICENSE_CERTIFICATE_BASE64`
但不可同時使用兩者。標準部署請使用：`TUIST_LICENSE`

::: warning EXPIRATION DATE
<!-- -->
授權許可證設有有效期限。當授權剩餘天數少於 30 天時，使用者在執行與伺服器互動的 Tuist 指令時將收到警告。若需續約授權，請聯繫
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

### 基礎環境設定{#base-environment-configuration}

| 環境變數                                  | 說明                                                                   | 必填  | 預設                                 | 範例                                                                 |                                                                                                                                    |
| ------------------------------------- | -------------------------------------------------------------------- | --- | ---------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | 從網際網路存取該實例的基礎網址                                                      | 是   |                                    | https://tuist.dev                                                  |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | 用於加密資訊的密鑰（例如 cookie 中的會話資料）                                          | 是   |                                    |                                                                    | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Pepper 用於生成雜湊密碼                                                      | 不   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | 用於生成隨機令牌的密鑰                                                          | 不   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | 32 位元組金鑰用於 AES-GCM 加密敏感資料                                            | 不   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | 當執行 ``` 並設定 `` ` 時，會將應用程式配置為使用 IPv6 位址                               | 不   | `0`                                | `1`                                                                |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | 應用程式應使用的記錄等級                                                         | 不   | `info`                             | [日誌等級](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | 您的 GitHub 應用程式名稱的 URL 版本                                             | 不   |                                    | `my-app`                                                           |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用於 GitHub 應用程式解鎖額外功能（例如自動發布 PR 評論）的 Base64 編碼私鑰                      | 不   | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                    |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | 用於解鎖 GitHub 應用程式額外功能（如自動發布 PR 評論）的私密金鑰。**建議改用 base64 編碼版本以避免特殊字元問題** | 不   | `-----BEGIN RSA...`                |                                                                    |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | 以逗號分隔的用戶代號清單，這些用戶擁有操作 URL 的存取權限                                      | 不   |                                    | `使用者1,使用者2`                                                        |                                                                                                                                    |
| `TUIST_WEB`                           | 啟用網頁伺服器端點                                                            | 不   | `1`                                | `1` 或`0`                                                           |                                                                                                                                    |

### 資料庫設定{#database-configuration}

以下環境變數用於設定資料庫連線：

| 環境變數                                 | 說明                                                                                                                        | 必填  | 預設        | 範例                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | 存取 Postgres 資料庫的 URL。請注意 URL 應包含驗證資訊                                                                                      | 是   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | 存取 ClickHouse 資料庫的 URL。請注意 URL 應包含驗證資訊                                                                                    | 不   |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | 當為真時，將使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連線至資料庫                                             | 不   | `1`       | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | 連接池中需保持開啟的連接數                                                                                                             | 不   | `10`      | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | 檢查從連接池中提取的所有連接是否超過排隊間隔的時間間隔（以毫秒為單位）[(更多資訊)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 不   | `300`     | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | 池用於判斷是否開始捨棄新連線的佇列閾值時間（單位：毫秒）[(更多資訊)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)        | 不   | `1000`    | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 緩衝區刷新之間的時間間隔（單位：毫秒）                                                                                            | 不   | `5000`    | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | 強制刷新前的最大 ClickHouse 緩衝區大小（以位元組為單位）                                                                                        | 不   | `1000000` | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | 要執行的 ClickHouse 緩衝區程序數量                                                                                                   | 不   | `5`       | `5`                                                                    |

### 驗證環境設定{#authentication-environment-configuration}

**我們透過[身分提供者 (IdP)](https://en.wikipedia.org/wiki/Identity_provider)
協助驗證流程。欲使用此功能，請確保伺服器環境中已存在所選提供者所需的所有環境變數。若缺少變數** ，Tuist 將跳過該提供者。

#### GitHub{#github}

我們建議使用[GitHub
App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)進行驗證，但您亦可採用[OAuth
App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。請務必在伺服器環境中包含
GitHub 指定的所有必要環境變數。若變數缺失，Tuist 將無法識別 GitHub 驗證。正確設定 GitHub App 的步驟如下：
- 在 GitHub 應用程式的通用設定中：
    - 複製`客戶端 ID` 並將其設定為`TUIST_GITHUB_APP_CLIENT_ID`
    - 建立並複製新的`客戶端密鑰` ，並將其設定為`TUIST_GITHUB_APP_CLIENT_SECRET`
    - 設定`回呼網址` 為`http://YOUR_APP_URL/users/auth/github/callback` 。`YOUR_APP_URL`
      亦可為您伺服器的 IP 位址。
- 需具備以下權限：
  - 儲存庫：
    - 拉取請求：閱讀與撰寫
  - 帳戶：
    - 電子郵件地址：僅限讀取

在`權限與事件` 的`帳戶權限` 區段中，將`電子郵件地址` 權限設為`唯讀` 。

接著您需要在 Tuist 伺服器運作的環境中公開下列環境變數：

| 環境變數                             | 說明                 | 必填  | 預設  | 範例                                         |
| -------------------------------- | ------------------ | --- | --- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | GitHub 應用程式的客戶端 ID | 是   |     | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 應用的客戶端密鑰           | 是   |     | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google{#google}

您可透過[OAuth
2](https://developers.google.com/identity/protocols/oauth2)設定Google驗證。需建立新型別的OAuth客戶端ID憑證，建立時請選擇「網路應用程式」作為應用程式類型，命名為`Tuist`
，並將重定向URI設為`{base_url}/users/auth/google/callback` ，其中`base_url` 為您託管服務的運作網址。
建立應用程式後，請複製客戶端 ID 與密鑰，並分別設定為環境變數：`GOOGLE_CLIENT_ID` 以及`GOOGLE_CLIENT_SECRET`

::: info CONSENT SCREEN SCOPES
<!-- -->
您可能需要建立同意畫面。建立時請務必新增以下權限範圍：`userinfo.email` ` openid` 並將應用程式標記為內部使用。
<!-- -->
:::

#### Okta{#okta}

您可透過[OAuth
2.0](https://oauth.net/2/)協議啟用Okta驗證功能。需依照<LocalizedLink href="/guides/integrations/sso#okta">此處說明</LocalizedLink>在Okta上[建立應用程式](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在設定 Okta 應用程式時取得客戶端 ID 與密鑰後，您需設定下列環境變數：

| 環境變數                         | 說明                                | 必填  | 預設  | 範例  |
| ---------------------------- | --------------------------------- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID`     | 用於對 Okta 進行驗證的客戶端 ID。此數字應為您的組織 ID | 是   |     |     |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用於對 Okta 進行驗證的客戶端密鑰               | 是   |     |     |

數字`1` 需替換為貴機構的組織編號。此編號通常為 1，但請務必查核資料庫確認。

### 儲存環境設定{#storage-environment-configuration}

Tuist 需要儲存空間來存放透過 API 上傳的文物。為使 Tuist 有效運作，務必設定其中一種支援的儲存解決方案（詳見**及** ）。

#### 符合 S3 標準的儲存空間{#s3compliant-storages}

您可使用任何符合 S3 標準的儲存供應商來存放工件。以下環境變數是驗證身分及設定與儲存供應商整合所需的：

| 環境變數                                                  | 說明                                                                 | 必填  | 預設       | 範例                                                            |
| ----------------------------------------------------- | ------------------------------------------------------------------ | --- | -------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` 或`AWS_ACCESS_KEY_ID`         | 用於對儲存供應商進行驗證的存取金鑰 ID                                               | 是   |          | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` 或`AWS_SECRET_ACCESS_KEY` | 用於對儲存供應商進行驗證的秘密存取金鑰                                                | 是   |          | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` 或`AWS_REGION`                       | 水桶所在的區域                                                            | 不   | `auto`   | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` 或`AWS_ENDPOINT`                   | 儲存供應商的終端點                                                          | 是   |          | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                | 存放成果檔案的儲存桶名稱                                                       | 是   |          | `tuist-artifacts`                                             |
| `TUIST_S3_CA_CERT_PEM`                                | 用於驗證 S3 HTTPS 連線的 PEM 編碼 CA 憑證。適用於採用自簽憑證或內部憑證授權機構的隔離環境。            | 不   | 系統 CA 套件 | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                            | 建立儲存提供者連線的超時設定（單位：毫秒）                                              | 不   | `3000`   | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                            | 從儲存供應商接收資料的超時設定（單位：毫秒）                                             | 不   | `5000`   | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                               | 儲存提供者的連線池超時設定（單位：毫秒）。使用`infinity` 設定無超時限制                          | 不   | `5000`   | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                         | 連線池中連線的最大閒置時間（單位：毫秒）。使用 ``` 或 `infinity` 設定值，或 `` ` 設定值以無限期維持連線存活。 | 不   | `無限`     | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                  | 每個連線池的最大連線數                                                        | 不   | `500`    | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                 | 要使用的連線池數量                                                          | 不   | 系統排程器數量  | `4`                                                           |
| `TUIST_S3_PROTOCOL`                                   | 連接儲存供應商時應使用的協定（`http1` 或`http2` ）                                  | 不   | `http1`  | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                               | URL 應否以儲存桶名稱作為子網域（虛擬主機）來建構                                         | 不   | `false`  | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
若您的儲存供應商為 AWS 且欲使用網頁身分憑證進行驗證，可將環境變數`TUIST_S3_AUTHENTICATION_METHOD`
設定為`aws_web_identity_token_from_env_vars` ，Tuist 將透過標準 AWS 環境變數採用此驗證方式。
<!-- -->
:::

#### Google Cloud Storage{#google-cloud-storage}
針對 Google Cloud
Storage，請參照[此文件指南](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)取得以下環境變數組：`AWS_ACCESS_KEY_ID`
` AWS_SECRET_ACCESS_KEY` ` AWS_ENDPOINT` 應設定為`https://storage.googleapis.com`
其餘環境變數設定方式與其他 S3 相容儲存服務相同。

### 電子郵件設定{#email-configuration}

Tuist 需透過電子郵件功能進行用戶驗證與交易通知（例如：密碼重設、帳戶通知）。目前僅支援**及** 作為郵件服務供應商。

| 環境變數                             | 說明                                      | 必填  | 預設                               | 範例                     |
| -------------------------------- | --------------------------------------- | --- | -------------------------------- | ---------------------- |
| `TUIST_MAILGUN_API_KEY`          | 用於 Mailgun 驗證的 API 金鑰                   | 是*  |                                  | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN`           | 將用於發送電子郵件的來源網域                          | 是*  |                                  | `mg.tuist.io`          |
| `TUIST_MAILING_FROM_ADDRESS`     | 將顯示於「寄件者」欄位的電子郵件地址                      | 是*  |                                  | `noreply@tuist.io`     |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 使用者回覆的選填回覆地址                            | 不   |                                  | `support@tuist.dev`    |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | 跳過新用戶註冊的電子郵件確認。啟用此功能後，用戶將自動確認並可在註冊後立即登入 | 不   | `true` 若未設定電子郵件，`false` 若已設定電子郵件 | `true`,`false`,`1`,`0` |

\* 僅當您需要發送電子郵件時，才需設定郵件配置變數。若未設定，系統將自動跳過郵件確認步驟

::: info SMTP SUPPORT
<!-- -->
目前尚未提供通用 SMTP 支援。若您需要在本地部署中使用 SMTP 功能，請聯繫
[contact@tuist.dev](mailto:contact@tuist.dev) 討論您的需求。
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
對於無網路連線或未設定電子郵件服務的本地安裝環境，系統預設會自動跳過電子郵件確認步驟。使用者註冊後即可立即登入。若已設定電子郵件服務但仍需跳過確認，請設定：`TUIST_SKIP_EMAIL_CONFIRMATION=true`
若需在設定電子郵件服務時強制執行確認，請設定：`TUIST_SKIP_EMAIL_CONFIRMATION=false`
<!-- -->
:::

### Git 平台設定{#git-platform-configuration}

Tuist 可 <LocalizedLink href="/guides/server/authentication">整合 Git
平台</LocalizedLink> 以提供額外功能，例如自動在您的拉取請求中發佈評論。

#### GitHub{#platform-github}

您需要[建立一個 GitHub
應用程式](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。若您先前已建立用於驗證的應用程式，可直接重複使用（除非您建立的是
OAuth GitHub 應用程式）。在`權限與事件` 的`儲存庫權限` 區段中，您還需將`拉取請求` 權限設定為`讀取與寫入` 。

除`TUIST_GITHUB_APP_CLIENT_ID` 及`TUIST_GITHUB_APP_CLIENT_SECRET` 外，您還需設定以下環境變數：

| 環境變數                           | 說明               | 必填  | 預設  | 範例                                   |
| ------------------------------ | ---------------- | --- | --- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub 應用程式的私密金鑰 | 是   |     | `-----BEGIN RSA PRIVATE KEY-----...` |

## 本地測試{#testing-locally}

我們提供完整的 Docker Compose 設定檔，包含所有必要依賴項，供您在部署至基礎架構前於本地機器測試 Tuist 伺服器：

- PostgreSQL 15 搭配 TimescaleDB 2.16 擴充套件（已廢棄）
- ClickHouse 25 用於分析
- ClickHouse Keeper 協調專員
- MinIO 用於 S3 相容儲存
- Redis 用於跨部署的持久化 KV 儲存（可選）
- pgweb 用於資料庫管理

::: danger LICENSE REQUIRED
<!-- -->
根據法律規定，運行 Tuist 伺服器（包含本地開發實例）必須具備有效的環境變數：`TUIST_LICENSE` 。如需授權許可，請聯繫
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
- MinIO 控制台：http://localhost:9003 (憑證：`tuist` /`tuist_dev_password`)
- MinIO API：http://localhost:9002
- pgweb (PostgreSQL 介面)：http://localhost:8081
- 普羅米修斯指標：http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

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
  Compose 設定檔
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse
  設定檔
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - ClickHouse Keeper 設定檔
- [.env.example](/server/self-host/.env.example) - 範例環境變數檔案

## 部署{#deployment}

官方 Tuist Docker 映像檔可於以下位置取得：
```
ghcr.io/tuist/tuist
```

### 拉取 Docker 映像檔{#pulling-the-docker-image}

您可透過執行以下指令取得該圖片：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

或提取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 映像檔{#deploying-the-docker-image}

Docker 映像的部署流程將因您選擇的雲端供應商及組織的持續部署策略而異。由於多數雲端解決方案與工具（如
[Kubernetes](https://kubernetes.io/)）皆以 Docker 映像為基礎運作單元，本節範例應能與您現有架構無縫整合。

::: warning
<!-- -->
若您的部署管道需驗證伺服器是否正常運作，可發送以下 HTTP 請求：`GET` 至`/ready` 並確認回應中包含狀態碼：`200`
<!-- -->
:::

#### 飛{#fly}

要在 [Fly](https://fly.io/) 上部署應用程式，您需要一個`fly.toml` 配置檔案。建議在持續部署 (CD)
管線中動態生成此檔案。以下提供參考範例供您使用：

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

接著執行`fly launch --local-only --no-deploy` 即可啟動應用程式。後續部署時，請勿執行`fly launch
--local-only` ，而需改用`fly deploy --local-only` 。由於 Fly.io 不允許拉取私有 Docker
映像檔，因此必須使用`--local-only` 參數。


## 普羅米修斯指標{#prometheus-metrics}

Tuist 透過`/metrics 及` 公開 Prometheus 指標，協助您監控自建實例。這些指標包含：

### Finch HTTP 客戶端指標{#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作為其 HTTP 客戶端，並提供關於 HTTP
請求的詳細指標：

#### 請求指標
- `tuist_prom_ex_finch_request_count_total` - Finch 請求總數（計數器）
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 請求持續時間（直方圖）
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
  - 時間區間：10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、2.5秒、5秒、10秒
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 請求異常總數（計數器）
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`kind`,`reason`

#### 連線池佇列指標
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在連接池佇列中等待的時間（直方圖）
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 桶：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 記錄連接在被使用前處於閒置狀態的時間（直方圖）
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 區間：10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、5秒、10秒
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 佇列異常總數（計數器）
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`kind`,`reason`

#### 連線指標
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立連線所耗費的時間（直方圖）
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`error`
  - 區間：10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、2.5秒、5秒
- `tuist_prom_ex_finch_connect_count_total` - 總連接嘗試次數（計數器）
  - 標籤：`finch_name`,`scheme`,`host`,`port`

#### 傳送指標
- `tuist_prom_ex_finch_send_duration_milliseconds` - 發送請求所耗時間（直方圖）
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 桶：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 記錄傳送前連接閒置時間（直方圖）
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 桶：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒

所有直方圖指標皆提供以下變體供詳細分析：`_bucket` ` _sum` ` _count`

### 其他指標

除了 Finch 指標外，Tuist 還提供以下指標：
- BEAM 虛擬機器效能
- 自訂業務邏輯指標（儲存空間、帳戶、專案等）
- 資料庫效能（使用 Tuist 主機基礎架構時）

## 操作{#operations}

Tuist 提供一組實用工具，位於`/ops/ 及` ，可用於管理您的實例。

::: warning Authorization
<!-- -->
僅當使用者名稱列於環境變數`TUIST_OPS_USER_HANDLES` 中者，方可存取`/ops/` 端點。
<!-- -->
:::

- **錯誤 (`/ops/errors`):**
  您可在此檢視應用程式中發生的意外錯誤。此功能有助於除錯與釐清問題根源，若您遭遇異常狀況，我們可能會請您提供此資訊。
- **儀表板 (`/ops/dashboard`):**
  您可檢視此儀表板以獲取應用程式效能與健康狀態的洞察（例如記憶體消耗、執行中的程序、請求數量）。此儀表板對於判斷您使用的硬體是否足以處理負載相當實用。
