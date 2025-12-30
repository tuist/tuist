---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# 自我主機安裝{#self-host-installation}

我們為需要對其基礎設施進行更多控制的組織提供自助託管版本的 Tuist 伺服器。此版本允許您在自己的基礎架構上託管 Tuist，確保資料的安全和隱私。

::: warning LICENSE REQUIRED
<!-- -->
自行託管 Tuist 需要合法有效的付費授權。預置版 Tuist 僅適用於企業計劃的組織。如果您對此版本感興趣，請聯絡
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

## 釋放速度{#release-cadence}

我們會持續釋出 Tuist 的新版本，因為新的可釋出變更會出現在主網站上。我們遵循 [semantic
versioning](https://semver.org/) 以確保可預期的版本與相容性。

主要元件用來標記 Tuist 伺服器中需要與內部使用者協調的突破性變更。您不應該期望我們會使用它，如果我們需要，請放心，我們會與您合作，使過渡順利。

## 持續部署{#continuous-deployment}

我們強烈建議您設定持續部署管道，每天自動部署最新版本的 Tuist。這可確保您永遠都能存取最新的功能、改進和安全更新。

以下是一個 GitHub Actions 工作流程範例，每天檢查並部署新版本：

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

## 運行時間要求{#runtime-requirements}

本節概述在您的基礎架構上託管 Tuist 伺服器的需求。

### 相容性矩陣{#compatibility-matrix}

Tuist 伺服器已通過測試，並與下列最低版本相容：

| 組件          | 最低版本   | 注意事項                    |
| ----------- | ------ | ----------------------- |
| PostgreSQL  | 15     | 使用 TimescaleDB 延伸       |
| TimescaleDB | 2.16.1 | 所需的 PostgreSQL 延伸 (已廢棄) |
| 點擊房屋        | 25     | 分析所需                    |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB 目前是 Tuist 伺服器所需的 PostgreSQL 延伸，用於時間序列資料儲存和查詢。然而，**TimescaleDB 已經廢棄**
，在不久的將來，當我們將所有的時間序列功能遷移到 ClickHouse 時，TimescaleDB 將不再是必要的依賴。目前，請確保您的 PostgreSQL
實例已安裝並啟用 TimescaleDB。
<!-- -->
:::

### 執行 Docker 虛擬化影像{#running-dockervirtualized-images}

我們透過 [GitHub
的容器註冊處](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)，將伺服器以
[Docker](https://www.docker.com/) 映像發行。

若要執行它，您的基礎架構必須支援執行 Docker 映像。請注意，大多數基礎結構供應商都支援它，因為它已經成為在生產環境中散佈和執行軟體的標準容器。

### Postgres 資料庫{#postgres-database}

除了執行 Docker 映像檔之外，您還需要一個具有 [TimescaleDB 擴充套件] (https://www.timescale.com/) 的
[Postgres 資料庫](https://www.postgresql.org/)，以儲存關聯性和時間序列資料。大多數基礎結構供應商都提供 Postgres
資料庫（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 和 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)）。

**需要 TimescaleDB 擴充套件：** Tuist 需要 TimescaleDB
擴充套件，以進行有效率的時間序列資料儲存和查詢。此擴充用於命令事件、分析和其他基於時間的功能。在執行 Tuist 之前，請確保您的 PostgreSQL
實例已安裝並啟用 TimescaleDB。

::: info MIGRATIONS
<!-- -->
Docker 映像的入口點會在啟動服務之前自動執行任何待定的模式遷移。如果因缺少 TimescaleDB 擴充套件而導致遷移失敗，您需要先在資料庫中安裝。
<!-- -->
:::

### ClickHouse 資料庫{#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 來儲存和查詢大量分析資料。ClickHouse 是**所需的**
，用於建立洞察力等功能，並會在我們逐步淘汰 TimescaleDB 時成為主要的時間序列資料庫。您可以選擇自行託管 ClickHouse 或使用其託管服務。

::: info MIGRATIONS
<!-- -->
Docker 映像的入口點會在啟動服務之前自動執行任何待定的 ClickHouse 方案遷移。
<!-- -->
:::

### 儲存{#storage}

您還需要一個解決方案來儲存檔案 (例如框架和函式庫的二進檔)。目前我們支援任何符合 S3 標準的儲存空間。

## 組態{#configuration}

服務的設定是在執行時透過環境變數完成。鑒於這些變數的敏感性，我們建議將它們加密並儲存到安全的密碼管理解決方案中。請放心，Tuist
會小心處理這些變數，確保它們不會顯示在日誌中。

::: info LAUNCH CHECKS
<!-- -->
必要的變數會在啟動時驗證。如果缺少任何變數，啟動將會失敗，錯誤訊息會詳細說明缺少的變數。
<!-- -->
:::

### 授權配置{#license-configuration}

作為內部使用者，您會收到一個授權金鑰，您需要將此金鑰顯示為環境變數。此金鑰用於驗證授權，並確保服務在合約條款內執行。

| 環境變數                               | 說明                                                                                                  | 必須  | 預設  | 範例                                        |
| ---------------------------------- | --------------------------------------------------------------------------------------------------- | --- | --- | ----------------------------------------- |
| `TUIST_LICENSE`                    | 簽署服務層級協議後提供的授權                                                                                      | 是*  |     | `******`                                  |
| `tuist_license_certificate_base64` | **是 `TUIST_LICENSE`** 的特殊替代品。Base64 編碼的公開憑證，用於伺服器無法與外部服務聯繫的空中封鎖環境中的離線授權驗證。僅在`TUIST_LICENSE` 無法使用時使用 | 是*  |     | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

* 必須提供`TUIST_LICENSE` 或`TUIST_LICENSE_CERTIFICATE_BASE64`
，但不能同時提供。標準部署使用`TUIST_LICENSE` 。

::: warning EXPIRATION DATE
<!-- -->
許可證有到期日。如果許可證在 30 天內到期，用戶在使用與伺服器互動的 Tuist 指令時會收到警告。如果您有興趣更新授權，請聯絡
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

### 基本環境配置{#base-environment-configuration}

| 環境變數                                  | 說明                                                                              | 必須  | 預設                                 | 範例                                                                  |                                                                                                                                    |
| ------------------------------------- | ------------------------------------------------------------------------------- | --- | ---------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | 從網際網路存取實體的基本 URL                                                                | 是   |                                    | https://tuist.dev                                                   |                                                                                                                                    |
| `tuist_secret_key_base`               | 用來加密資訊的金鑰 (例如 cookie 中的會話)                                                      | 是   |                                    |                                                                     | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `tuist_secret_key_password`           | Pepper 生成散列密碼                                                                   | 沒有  | `$tuist_secret_key_base`           |                                                                     |                                                                                                                                    |
| `tuist_secret_key_tokens`             | 用於產生隨機代幣的密匙                                                                     | 沒有  | `$tuist_secret_key_base`           |                                                                     |                                                                                                                                    |
| `tuist_secret_key_encryption`         | 32 位元組金鑰用於 AES-GCM 敏感資料加密                                                       | 沒有  | `$tuist_secret_key_base`           |                                                                     |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | 當`1` 時，它會設定應用程式使用 IPv6 位址                                                       | 沒有  | `0`                                | `1`                                                                 |                                                                                                                                    |
| `tuist_log_level`                     | 應用程式要使用的日誌層級                                                                    | 沒有  | `資訊`                               | [日誌層級](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels)。 |                                                                                                                                    |
| `tuist_github_app_name`               | GitHub 應用程式名稱的 URL 版本                                                           | 沒有  |                                    | `我的應用程式`                                                            |                                                                                                                                    |
| `tuist_github_app_private_key_base64` | 基於 64 編碼的私人密碼，用於 GitHub 應用程式，以解鎖額外的功能，例如張貼自動 PR 評論。                             | 沒有  | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                     |                                                                                                                                    |
| `tuist_github_app_private_key`        | GitHub 應用程式用來解鎖額外功能（例如張貼自動 PR 評論）的私密金鑰。**我們建議使用 base64-encoded 版本，以避免特殊字符的問題。** | 沒有  | `-----BEGIN RSA...`                |                                                                     |                                                                                                                                    |
| `tuist_ops_user_handles`              | 以逗號分隔、可存取操作 URL 的使用者句柄清單                                                        | 沒有  |                                    | `使用者1,使用者2`                                                         |                                                                                                                                    |
| `TUIST_WEB`                           | 啟用網路伺服器端點                                                                       | 沒有  | `1`                                | `1` 或`0`                                                            |                                                                                                                                    |

### 資料庫設定{#database-configuration}

下列環境變數用於設定資料庫連線：

| 環境變數                                 | 說明                                                                                                                              | 必須  | 預設        | 範例                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | 存取 Postgres 資料庫的 URL。請注意 URL 應包含驗證資訊                                                                                            | 是   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `tuist_clickhouse_url`               | 存取 ClickHouse 資料庫的 URL。請注意 URL 應包含驗證資訊                                                                                          | 沒有  |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `tuist_use_ssl_for_database`         | 為真時，會使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 連線至資料庫                                                    | 沒有  | `1`       | `1`                                                                    |
| `tuist_database_pool_size`           | 連線池中要保持開啟的連線數                                                                                                                   | 沒有  | `10`      | `10`                                                                   |
| `tuist_database_queue_target`        | 用來檢查所有從連線池檢出的連線所花的時間是否超過佇列間隔的間隔 (以毫秒為單位)[(更多資訊)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)。 | 沒有  | `300`     | `300`                                                                  |
| `tuist_database_queue_interval`      | 在佇列中的臨界時間 (以毫秒為單位)，供池用來決定是否應該開始丟棄新連線 [(更多資訊)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)。    | 沒有  | `1000`    | `1000`                                                                 |
| `tuist_clickhouse_flush_interval_ms` | ClickHouse 緩衝區刷新的時間間隔，以毫秒為單位                                                                                                    | 沒有  | `5000`    | `5000`                                                                 |
| `tuist_clickhouse_max_buffer_size`   | 強制刷新前的最大 ClickHouse 緩衝區大小 (位元組)                                                                                                 | 沒有  | `1000000` | `1000000`                                                              |
| `tuist_clickhouse_buffer_pool_size`  | 要執行的 ClickHouse 緩衝程序數量                                                                                                          | 沒有  | `5`       | `5`                                                                    |

### 驗證環境設定{#authentication-environment-configuration}

我們透過 [身分提供者
(IdP)](https://en.wikipedia.org/wiki/Identity_provider)，協助進行驗證。要使用此功能，請確保伺服器的環境中存在所選提供者的所有必要環境變數。**遺失變數**
將導致 Tuist 繞過該提供者。

#### GitHub{#github}

我們建議使用 [GitHub
應用程式](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)，但您也可以使用
[OAuth
應用程式](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。確保在伺服器環境中包含
GitHub 指定的所有重要環境變數。缺少變量會導致 Tuist 忽略 GitHub 認證。正確設定 GitHub 應用程式：
- 在 GitHub 應用程式的一般設定中：
    - 複製`客戶端 ID` ，並設定為`TUIST_GITHUB_APP_CLIENT_ID`
    - 建立並複製新的`客戶端秘密` ，並將其設定為`TUIST_GITHUB_APP_CLIENT_SECRET`
    - 將`Callback URL` 設定為`http://YOUR_APP_URL/users/auth/github/callback`
      。`YOUR_APP_URL` 也可以是您伺服器的 IP 位址。
- 需要以下權限：
  - 儲存庫：
    - 拉取請求：讀寫
  - 帳戶：
    - 電子郵件地址：唯讀

在`Permissions and events` 的`Account permissions` 部分，將`Email addresses` 權限設定為`唯讀`
。

然後，您需要在 Tuist 伺服器執行的環境中公開下列環境變數：

| 環境變數                             | 說明                 | 必須  | 預設  | 範例                                         |
| -------------------------------- | ------------------ | --- | --- | ------------------------------------------ |
| `tuist_github_app_client_id`     | GitHub 應用程式的用戶端 ID | 是   |     | `Iv1.a629723000043722`                     |
| `tuist_github_app_client_secret` | 應用程式的用戶端秘密         | 是   |     | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google{#google}

您可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 設定
Google 認證。為此，您需要建立一個 OAuth 客戶 ID 類型的新憑證。建立憑證時，選擇「Web 應用程式」作為應用程式類型，將其命名為`Tuist`
，並將重定向 URI 設定為`{base_url}/users/auth/google/callback` ，其中`base_url` 是您的託管服務所執行的
URL。建立應用程式後，複製用戶端 ID 和 secret，並分別設定為環境變數`GOOGLE_CLIENT_ID`
和`GOOGLE_CLIENT_SECRET` 。

::: info CONSENT SCREEN SCOPES
<!-- -->
您可能需要建立同意畫面。這樣做時，請務必加入`userinfo.email` 和`openid` 範圍，並將應用程式標示為內部應用程式。
<!-- -->
:::

#### Okta{#okta}

您可以透過 [OAuth 2.0](https://oauth.net/2/) 通訊協定啟用 Okta 的驗證功能。您必須依照
<LocalizedLink href="/guides/integrations/sso#okta"> 這些指示 </LocalizedLink> 在
Okta 上
[建立應用程式](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

當您在設定 Okta 應用程式時取得用戶端 id 和 secret 後，您需要設定下列環境變數：

| 環境變數                         | 說明                             | 必須  | 預設  | 範例  |
| ---------------------------- | ------------------------------ | --- | --- | --- |
| `tuist_okta_1_client_id`     | 用於驗證 Okta 的用戶端 ID。數字應該是您的組織 ID | 是   |     |     |
| `tuist_okta_1_client_secret` | 用於驗證 Okta 的用戶端秘密               | 是   |     |     |

`1` 需要用您的組織 ID 取代。這通常是 1，但請檢查您的資料庫。

### 儲存環境配置{#storage-environment-configuration}

Tuist 需要儲存空間來存放透過 API 上傳的作品。**必須設定其中一個支援的儲存解決方案** ，才能讓 Tuist 有效運作。

#### 符合 S3 的儲存設備{#s3compliant-storages}

您可以使用任何符合 S3 標準的儲存提供者來儲存工件。驗證和設定與儲存提供者的整合需要下列環境變數：

| 環境變數                                                  | 說明                                                               | 必須  | 預設      | 範例                                                           |
| ----------------------------------------------------- | ---------------------------------------------------------------- | --- | ------- | ------------------------------------------------------------ |
| `TUIST_S3_ACCESS_KEY_ID` 或`AWS_ACCESS_KEY_ID`         | 存取金鑰 ID，用來驗證儲存提供者                                                | 是   |         | `AKIAIOSFOD`                                                 |
| `TUIST_S3_SECRET_ACCESS_KEY` 或`AWS_SECRET_ACCESS_KEY` | 用於驗證儲存提供者的秘密存取金鑰                                                 | 是   |         | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                   |
| `TUIST_S3_REGION` 或`AWS_REGION`                       | 水桶所在的區域                                                          | 沒有  | `自動`    | `us-west-2`                                                  |
| `TUIST_S3_ENDPOINT` 或`AWS_ENDPOINT`                   | 儲存提供者的端點                                                         | 是   |         | `https://s3.us-west-2.amazonaws.com`                         |
| `tuist_s3_bucket_name`                                | 儲存藝術品的水桶名稱                                                       | 是   |         | `tuist-artifacts`                                            |
| `tuist_s3_ca_cert_pem`                                | 用於驗證 S3 HTTPS 連線的 PEM 編碼 CA 憑證。適用於具有自簽署憑證或內部憑證授權的 air-gapped 環境。 | 沒有  | 系統 CA 包 | `-----BEGIN CERTIFICATE-----n...\n-----END CERTIFICATE-----` |
| `tuist_s3_connect_timeout`                            | 與儲存提供者建立連線的逾時時間（以毫秒為單位                                           | 沒有  | `3000`  | `3000`                                                       |
| `tuist_s3_receive_timeout`                            | 從儲存提供者接收資料的逾時時間（以毫秒為單位                                           | 沒有  | `5000`  | `5000`                                                       |
| `tuist_s3_pool_timeout`                               | 連線池到儲存提供者的逾時時間（以毫秒為單位）。使用`infinity` 表示無超時                        | 沒有  | `5000`  | `5000`                                                       |
| `tuist_s3_pool_max_idle_time`                         | 池中連線的最長閒置時間 (以毫秒為單位)。使用`infinity` 無限期保持連線存活                      | 沒有  | `淼`     | `60000`                                                      |
| `tuist_s3_pool_size`                                  | 每個池的最大連線數                                                        | 沒有  | `500`   | `500`                                                        |
| `tuist_s3_pool_count`                                 | 要使用的連線池數量                                                        | 沒有  | 系統排程器數量 | `4`                                                          |
| `tuist_s3_protocol`                                   | 連線到儲存提供者時要使用的通訊協定 (`http1` 或`http2`)                             | 沒有  | `http1` | `http1`                                                      |
| `tuist_s3_virtual_host`                               | URL 是否應與作為子網域 (虛擬主機) 的水桶名稱一起建立                                   | 沒有  | `假的`    | `1`                                                          |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
如果您的儲存設備提供者是 AWS，而您想使用 Web 身份令牌進行驗證，您可以將環境變數`TUIST_S3_AUTHENTICATION_METHOD`
設定為`aws_web_identity_token_from_env_vars` ，Tuist 將使用傳統的 AWS 環境變數使用該方法。
<!-- -->
:::

#### Google 雲端儲存{#google-cloud-storage}
對於 Google Cloud Storage，請遵循 [these
docs](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)
以取得`AWS_ACCESS_KEY_ID` 和`AWS_SECRET_ACCESS_KEY` 對。`AWS_ENDPOINT`
應設為`https://storage.googleapis.com` 。其他環境變數與任何其他 S3 相容的儲存相同。

### 電子郵件設定{#email-configuration}

Tuist 需要電子郵件功能來進行使用者驗證和交易通知 (例如密碼重設、帳戶通知)。目前，**僅支援 Mailgun** 作為電子郵件供應商。

| 環境變數                              | 說明                                      | 必須  | 預設                                 | 範例                     |
| --------------------------------- | --------------------------------------- | --- | ---------------------------------- | ---------------------- |
| `tuist_mailgun_api_key`           | 驗證 Mailgun 的 API 金鑰                     | 是*  |                                    | `key-1234567890abcdef` |
| `tuist_mailing_domain`            | 發送電子郵件的網域                               | 是*  |                                    | `mg.tuist.io`          |
| `tuist_mailing_from_address`      | 將出現在「寄件者」欄位的電子郵件地址                      | 是*  |                                    | `noreply@tuist.io`     |
| `tuist_mailing_reply_too_address` | 使用者回覆的可選回覆至地址                           | 沒有  |                                    | `support@tuist.dev`    |
| `tuist_skip_email_confirmation`   | 跳過新使用者註冊的電子郵件確認。啟用後，使用者註冊後會自動確認，並可立即登入。 | 沒有  | `true` 如果未設定電子郵件，`false` 如果已設定電子郵件 | `true`,`false`,`1`,`0` |

\* Email 配置變數只有在您想要傳送電子郵件時才需要。如果沒有設定，會自動跳過電子郵件確認。

::: info SMTP SUPPORT
<!-- -->
目前不提供一般 SMTP 支援。如果您的內部部署需要 SMTP 支援，請聯絡
[contact@tuist.dev](mailto:contact@tuist.dev) 討論您的需求。
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
對於沒有網際網路存取或電子郵件供應商設定的內部安裝，預設會自動跳過電子郵件確認。使用者註冊後可立即登入。如果您已設定電子郵件，但仍想跳過確認，請設定`TUIST_SKIP_EMAIL_CONFIRMATION=true`
。若要在設定電子郵件時要求電子郵件確認，請設定`TUIST_SKIP_EMAIL_CONFIRMATION=false` 。
<!-- -->
:::

### Git 平台設定{#git-platform-configuration}

Tuist 可以 <LocalizedLink href="/guides/server/authentication"> 整合 Git 平台</LocalizedLink>，提供額外的功能，例如自動在您的 pull request 中發佈註解。

#### GitHub{#platform-github}

您需要 [建立一個 GitHub
應用程式](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。除非您建立了
OAuth GitHub 應用程式，否則您可以重複使用您建立的那個用於驗證的應用程式。在`Permissions and events`'`Repository
permissions` 部分，您需要額外設定`Pull requests` 權限為`Read and write` 。

在`TUIST_GITHUB_APP_CLIENT_ID` 和`TUIST_GITHUB_APP_CLIENT_SECRET` 之上，您需要以下環境變數：

| 環境變數                           | 說明               | 必須  | 預設  | 範例                                   |
| ------------------------------ | ---------------- | --- | --- | ------------------------------------ |
| `tuist_github_app_private_key` | GitHub 應用程式的私密金鑰 | 是   |     | `-----begin rsa private key-----...` |

## 本地測試{#testing-locally}

我們提供全面的 Docker Compose 設定，其中包含所有必要的相依性，以便在部署到您的基礎架構之前，在本機上測試 Tuist 伺服器：

- PostgreSQL 15 搭配 TimescaleDB 2.16 延伸 (已廢棄)
- ClickHouse 25 用於分析
- 用於協調的 ClickHouse Keeper
- 適用於 S3 相容儲存設備的 MinIO
- Redis 用於跨部署的持久性 KV 儲存（可選）
- 用於資料庫管理的 pgweb

::: danger LICENSE REQUIRED
<!-- -->
執行 Tuist 伺服器，包括本機開發實體，必須依法取得有效的`TUIST_LICENSE` 環境變數。如果您需要授權，請聯絡
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

**快速入門：**

1. 下載組態檔案：
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

4. 透過 http://localhost:8080 存取伺服器

**服務端點：**
- Tuist 伺服器: http://localhost:8080
- MinIO 控制台： http://localhost:9003 (憑證：`tuist` /`tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus Metrics: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**常用指令：**

檢查服務狀態：
```bash
docker compose ps
# or: podman compose ps
```

檢視記錄：
```bash
docker compose logs -f tuist
```

停止服務：
```bash
docker compose down
```

重設一切（刪除所有資料）：
```bash
docker compose down -v
```

**設定檔案：**
- [docker-compose.yml](/server/self-host/docker-compose.yml)- 完成 Docker Compose
  設定
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml)- ClickHouse
  配置
- [Clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)-
  ClickHouse Keeper 設定
- [.env.example](/server/self-host/.env.example)- 環境變數檔案範例

## 部署{#deployment}

官方的 Tuist Docker 映像檔位於以下網址：
```
ghcr.io/tuist/tuist
```

### 拉取 Docker 映像{#pulling-the-docker-image}

您可以執行下列指令擷取影像：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

或拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 映像{#deploying-the-docker-image}

Docker 映像的部署流程會根據您選擇的雲供應商和組織的持續部署方法而有所不同。由於大多數雲端解決方案和工具 (例如
[Kubernetes](https://kubernetes.io/))，都使用 Docker 映像作為基本單位，因此本節中的範例應該與您現有的設定相當吻合。

::: warning
<!-- -->
如果您的部署管道需要驗證伺服器是否正常運作，您可以傳送`GET` HTTP 請求到`/ready` ，並在回應中斷言`200` 狀態碼。
<!-- -->
:::

#### 飛行{#fly}

若要在 [Fly](https://fly.io/) 上部署應用程式，您需要`fly.toml` 配置檔案。請考慮在您的持續部署 (CD)
管道中動態產生。以下是供您使用的參考範例：

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

然後，您可以執行`fly launch --local-only --no-deploy` 來啟動應用程式。在之後的部署中，您不需要執行`fly launch
--local-only` ，而是需要執行`fly deploy --local-only` 。Fly.io 不允許拉取私有的 Docker
映像，這就是為什麼我們需要使用`--local-only` 這個旗號。


## 普羅米修斯度量{#prometheus-metrics}

Tuist 在`/metrics` 揭露 Prometheus metrics，以協助您監控自託管的實例。這些指標包括

### Finch HTTP 用戶端指標{#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作為 HTTP 客戶端，並揭露 HTTP 請求的詳細指標：

#### 要求度量
- `tuist_prom_ex_finch_request_count_total` - Finch 請求總數 (計數器)
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 請求的持續時間 (直方圖)
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
  - 桶：10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 請求例外總數 (計數器)
  - 標籤：`finch_name`,`method`,`scheme`,`host`,`port`,`kind`,`reason`

#### 連線池佇列指標
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 連線池佇列中等待的時間 (直方圖)
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 桶：1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 連線在使用前的閒置時間 (直方圖)
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 桶：10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、5秒、10秒
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 佇列異常總數 (計數器)
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`kind`,`reason`

#### 連線度量
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立連線所花的時間 (直方圖)
  - 標籤：`finch_name`,`scheme`,`host`,`port`,`錯誤`
  - 桶：10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - 連線嘗試總次數 (計數器)
  - Labels:`finch_name`,`scheme`,`host`,`port`

#### 傳送指標
- `tuist_prom_ex_finch_send_duration_milliseconds` - 傳送要求所花的時間 (直方圖)
  - Labels:`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 桶：1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 連線在傳送前閒置的時間 (直方圖)
  - Labels:`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 桶：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒

所有直方圖度量都提供`_bucket`,`_sum`, 以及`_count` 變數，以供詳細分析。

### 其他指標

除了 Finch 測量標準之外，Tuist 還提供下列測量標準：
- BEAM 虛擬機器效能
- 自訂業務邏輯指標（儲存、帳戶、專案等）
- 資料庫效能 (使用 Tuist 主機架構時)

## 營運{#operations}

Tuist 在`/ops/` 下提供了一套公用程式，您可以使用這些公用程式來管理您的實體。

::: warning Authorization
<!-- -->
只有句柄列在`TUIST_OPS_USER_HANDLES` 環境變數中的人才能存取`/ops/` 端點。
<!-- -->
:::

- **錯誤 (`/ops/errors`)：**
  您可以檢視應用程式中發生的意外錯誤。這對於調試和了解出錯的原因非常有用，如果您遇到問題，我們可能會請您與我們分享這些資訊。
- **儀表板 (`/ops/dashboard`)：** 您可以檢視儀表板，以深入瞭解應用程式的效能與健康狀況
  (例如：記憶體消耗、執行中的進程、請求數量)。這個儀表板對於了解您使用的硬體是否足以處理負載相當有用。
