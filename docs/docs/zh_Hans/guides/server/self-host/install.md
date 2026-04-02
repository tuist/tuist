---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# 自主托管安装{#self-host-installation}

我们为需要对基础设施拥有更多控制权的组织提供 Tuist 服务器的自托管版本。此版本允许您在自己的基础设施上托管 Tuist，确保您的数据始终安全且私密。

::: warning LICENSE REQUIRED
<!-- -->
自托管版 Tuist 需要合法有效的付费许可证。Tuist 的本地部署版本仅面向订阅了企业版计划的组织。如果您对此版本感兴趣，请联系
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

## 发布频率{#release-cadence}

随着可发布的变更合并到主分支，我们会持续发布 Tuist 的新版本。我们遵循 [语义化版本控制](https://semver.org/)
以确保版本号的可预测性和兼容性。

该主要组件用于标记 Tuist
服务器中的破坏性变更，此类变更需要与本地部署用户进行协调。您不应预期我们会使用它，但万一需要使用，请放心，我们将与您通力合作，确保过渡过程顺利。

## 持续部署{#continuous-deployment}

我们强烈建议您设置一个持续部署管道，每天自动部署 Tuist 的最新版本。这样可以确保您始终能够使用最新的功能、改进和安全更新。

以下是一个示例 GitHub Actions 工作流，用于每日检查并部署新版本：

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

## 运行环境要求{#runtime-requirements}

本节概述了在您的基础设施上托管 Tuist 服务器的相关要求。

### 兼容性对照表{#compatibility-matrix}

Tuist 服务器已经过测试，兼容以下最低版本：

| 组件          | 最低版本   | 注释                     |
| ----------- | ------ | ---------------------- |
| PostgreSQL  | 15     | 使用 TimescaleDB 扩展      |
| TimescaleDB | 2.16.1 | 必需的 PostgreSQL 扩展（已弃用） |
| ClickHouse  | 25     | 分析所需                   |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB 目前是 Tuist 服务器必需的 PostgreSQL 扩展，用于时间序列数据的存储和查询。然而，**TimescaleDB
已被废弃** ，随着我们将所有时间序列功能迁移至 ClickHouse，它将在不久的将来不再作为必需依赖项。目前，请确保您的 PostgreSQL
实例已安装并启用了 TimescaleDB。
<!-- -->
:::

### 运行 Docker 虚拟化镜像{#running-dockervirtualized-images}

我们通过 [GitHub
容器注册表](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
以 [Docker](https://www.docker.com/) 镜像的形式发布该服务器。

要运行它，您的基础设施必须支持运行 Docker 镜像。请注意，大多数基础设施提供商都支持这一点，因为 Docker 已成为生产环境中分发和运行软件的标准容器。

### Postgres 数据库{#postgres-database}

除了运行 Docker 镜像外，您还需要一个安装了 [TimescaleDB 扩展](https://www.timescale.com/) 的
[Postgres 数据库](https://www.postgresql.org/) 来存储关系型和时间序列数据。大多数基础设施提供商都将其服务中包含
Postgres 数据库（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 和 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)）。

**需要 TimescaleDB 扩展：** Tuist 需要 TimescaleDB
扩展才能高效存储和查询时间序列数据。该扩展用于命令事件、分析及其他基于时间的功能。在运行 Tuist 之前，请确保您的 PostgreSQL 实例已安装并启用了
TimescaleDB。

::: info MIGRATIONS
<!-- -->
Docker 镜像的 entrypoint 会在启动服务前自动运行任何待处理的模式迁移。如果因缺少 TimescaleDB
扩展而导致迁移失败，您需要先在数据库中安装该扩展。
<!-- -->
:::

### ClickHouse 数据库{#clickhouse-database}

Tuist 使用 [ClickHouse](https://clickhouse.com/) 来存储和查询大量分析数据。ClickHouse
是**构建洞察等功能所必需的** ，并将随着我们逐步淘汰 TimescaleDB 而成为主要的时间序列数据库。您可以选择自行托管 ClickHouse
或使用其托管服务。

::: info MIGRATIONS
<!-- -->
Docker 镜像的 entrypoint 会在启动服务之前自动运行任何待处理的 ClickHouse 模式迁移。
<!-- -->
:::

### 存储{#storage}

您还需要一个用于存储文件（例如框架和库的二进制文件）的解决方案。目前我们支持任何符合 S3 规范的存储服务。

::: tip OPTIMIZED CACHING
<!-- -->
如果您的主要目的是自建存储二进制文件的存储桶并降低缓存延迟，可能无需自行托管整个服务器。您可以自行托管缓存节点，并将它们连接到托管的 Tuist
服务器或您自行托管的服务器。

请参阅 <LocalizedLink href="/guides/cache/self-host">缓存自主托管指南</LocalizedLink>。
<!-- -->
:::

## 配置 {#configuration}

该服务的配置通过运行时环境变量完成。鉴于这些变量的敏感性，我们建议将其加密并存储在安全的密码管理解决方案中。请放心，Tuist
会极其谨慎地处理这些变量，确保它们绝不会出现在日志中。

::: info LAUNCH CHECKS
<!-- -->
启动时会验证必要的变量。如果缺少任何变量，程序将无法启动，错误信息中会详细列出缺失的变量。
<!-- -->
:::

### 许可证配置{#license-configuration}

作为本地部署用户，您将收到一个许可证密钥，需要将其设置为环境变量。该密钥用于验证许可证，并确保服务在协议条款范围内运行。

| 环境变量                               | 描述                                                                                                      | 必需  | 默认值 | 示例                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------- | --- | --- | ----------------------------------------- |
| `TUIST_LICENSE`                    | 签署服务级别协议后提供的许可                                                                                          | 是*  |     | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **`TUIST_LICENSE` 的特殊替代方案** 。这是用于在服务器无法连接外部服务的物理隔离环境中进行离线许可证验证的 Base64 编码公共证书。仅在无法使用`TUIST_LICENSE` 时使用 | 是*  |     | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* 必须提供`TUIST_LICENSE` 或`TUIST_LICENSE_CERTIFICATE_BASE64`
其中之一，但不可同时提供两者。标准部署请使用`TUIST_LICENSE` 。

::: warning EXPIRATION DATE
<!-- -->
许可证设有有效期。若许可证在30天内到期，用户在使用与服务器交互的Tuist命令时将收到警告。如需续订许可证，请联系
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

### 基础环境配置{#base-environment-configuration}

| 环境变量                                  | 描述                                                                     | 必需  | 默认值                                | 示例                                                                 |                                                                                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------- | --- | ---------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | 用于从互联网访问该实例的基准 URL                                                     | 是   |                                    | https://tuist.dev                                                  |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | 用于加密信息（例如 Cookie 中的会话）的密钥                                              | 是   |                                    |                                                                    | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | 使用 Pepper 生成哈希密码                                                       | 否   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | 生成随机令牌的密钥                                                              | 否   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | 用于对敏感数据进行 AES-GCM 加密的 32 字节密钥                                          | 否   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | 当执行 ``1` ` 时，会将应用配置为使用 IPv6 地址                                         | 否   | `0`                                | `1`                                                                |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | 应用程序应使用的日志级别                                                           | 否   | `info`                             | [日志级别](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | 您 GitHub 应用名称的 URL 版本                                                  | 否   |                                    | `my-app`                                                           |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用于 GitHub 应用的 Base64 编码私钥，用于解锁额外功能，例如发布自动 PR 评论                        | 否   | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                    |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | 用于 GitHub 应用解锁额外功能（如发布自动 PR 评论）的私钥。**我们建议改用 base64 编码版本，以避免特殊字符引发的问题** | 否   | `-----BEGIN RSA...`                |                                                                    |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | 一个以逗号分隔的用户标识符列表，这些用户具有访问操作 URL 的权限                                     | 否   |                                    | `user1,user2`                                                      |                                                                                                                                    |
| `TUIST_WEB`                           | 启用 Web 服务器端点                                                           | 否   | `1`                                | `1` 或`0`                                                           |                                                                                                                                    |

### 数据库配置{#database-configuration}

以下环境变量用于配置数据库连接：

| 环境变量                                 | 描述                                                                                                                           | 必需  | 默认值       | 示例                                                                     |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | 访问 Postgres 数据库的 URL。请注意，该 URL 应包含身份验证信息                                                                                     | 是   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | 访问 ClickHouse 数据库的 URL。请注意，该 URL 应包含身份验证信息                                                                                   | 否   |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | 当为 true 时，使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 连接数据库                                             | 否   | `1`       | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | 连接池中应保持打开的连接数                                                                                                                | 否   | `10`      | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | 用于检查从连接池中检出的所有连接是否超过队列间隔的时间间隔（以毫秒为单位）[(更多信息)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)  | 否   | `300`     | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | 队列中的阈值时间（以毫秒为单位），连接池将根据该时间决定是否开始丢弃新连接 [(更多信息)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 否   | `1000`    | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 缓冲区刷新之间的间隔时间（以毫秒为单位）                                                                                              | 否   | `5000`    | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | 强制刷新前 ClickHouse 缓冲区的最大大小（单位：字节）                                                                                             | 否   | `1000000` | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | 要运行的 ClickHouse 缓冲区进程数量                                                                                                      | 否   | `5`       | `5`                                                                    |

### 身份验证环境配置{#authentication-environment-configuration}

我们通过 [身份提供商 (IdP)](https://en.wikipedia.org/wiki/Identity_provider)
支持身份验证。要使用此功能，请确保服务器环境中已设置所选提供商所需的所有环境变量。**若缺少变量** ，Tuist 将跳过该提供商。

#### GitHub{#github}

我们建议使用 [GitHub
App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)
进行身份验证，但您也可以使用 [OAuth
App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。请确保在服务器环境中包含
GitHub 指定的所有必要环境变量。缺少这些变量会导致 Tuist 忽略 GitHub 身份验证。要正确设置 GitHub App：
- 在 GitHub 应用的通用设置中：
    - 复制`中的客户端 ID` ，并将其设置为`TUIST_GITHUB_APP_CLIENT_ID`
    - 创建并复制新的`客户端密钥` ，并将其设置为`TUIST_GITHUB_APP_CLIENT_SECRET`
    - 将`的回调 URL` 设置为`http://YOUR_APP_URL/users/auth/github/callback`
      。`YOUR_APP_URL` 也可以是您服务器的 IP 地址。
- 需要以下权限：
  - 仓库：
    - 拉取请求：读写
  - 账户：
    - 电子邮件地址：只读

在`权限和事件` 的`账户权限` 部分，将`电子邮件地址` 权限设置为`只读` 。

随后，您需要在 Tuist 服务器运行的环境中设置以下环境变量：

| 环境变量                             | 描述               | 必需  | 默认值 | 示例                                         |
| -------------------------------- | ---------------- | --- | --- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | GitHub 应用的客户端 ID | 是   |     | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 该应用程序的客户端密钥      | 是   |     | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google{#google}

您可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 配置
Google 身份验证。为此，您需要创建一个类型为 OAuth 客户端 ID 的新凭据。创建凭据时，请选择“Web
应用程序”作为应用类型，将其命名为`Tuist` ，并将重定向 URI 设置为`{base_url}/users/auth/google/callback`
，其中`base_url` 是您托管服务的运行 URL。 创建应用后，复制客户端 ID
和密钥，并将其分别设置为环境变量：`（GOOGLE_CLIENT_ID）` 和`（GOOGLE_CLIENT_SECRET）` 。

::: info CONSENT SCREEN SCOPES
<!-- -->
您可能需要创建一个同意屏幕。创建时，请务必添加`userinfo.email` 和`openid` 权限范围，并将应用标记为内部应用。
<!-- -->
:::

#### Okta{#okta}

您可以通过 [OAuth 2.0](https://oauth.net/2/) 协议启用 Okta 身份验证。您需要在 Okta 上
[创建一个应用](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)，具体请按照
<LocalizedLink href="/guides/integrations/sso#okta">这些说明</LocalizedLink> 操作。

在设置 Okta 应用程序并获取客户端 ID 和密钥后，您需要设置以下环境变量：

| 环境变量                         | 描述                                   | 必需  | 默认值 | 示例  |
| ---------------------------- | ------------------------------------ | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID`     | 用于在 Okta 上进行身份验证的客户端 ID。该数字应为您的组织 ID | 是   |     |     |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用于对 Okta 进行身份验证的客户端密钥                | 是   |     |     |

数字`1` 需要替换为您的组织 ID。通常该值为 1，但请在数据库中确认。

### 存储环境配置{#storage-environment-configuration}

**Tuist 需要存储空间来存放通过 API 上传的工件。配置一种受支持的存储方案** 对 Tuist 的有效运行至关重要。

#### 符合 S3 标准的存储{#s3compliant-storages}

您可以使用任何符合 S3 标准的存储提供商来存储构建产物。以下环境变量用于验证身份并配置与存储提供商的集成：

| 环境变量                                                  | 描述                                                         | 必需  | 默认值        | 示例                                                            |
| ----------------------------------------------------- | ---------------------------------------------------------- | --- | ---------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` 或`AWS_ACCESS_KEY_ID`         | 用于对存储提供商进行身份验证的访问密钥 ID                                     | 是   |            | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` 或`AWS_SECRET_ACCESS_KEY` | 用于对存储提供商进行身份验证的密钥                                          | 是   |            | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` 或`AWS_REGION`                       | 存储桶所在的区域                                                   | 否   | `auto`     | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` 或`AWS_ENDPOINT`                   | 存储提供程序的端点                                                  | 是   |            | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                | 用于存储构建产物的存储桶名称                                             | 是   |            | `tuist-artifacts`                                             |
| `TUIST_S3_CA_CERT_PEM`                                | 用于验证 S3 HTTPS 连接的 PEM 编码 CA 证书。适用于使用自签名证书或内部证书颁发机构的物理隔离环境。 | 否   | 系统 CA 包    | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                            | 与存储提供商建立连接的超时时间（单位：毫秒）                                     | 否   | `3000`     | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                            | 从存储提供商接收数据的超时时间（以毫秒为单位）                                    | 否   | `5000`     | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                               | 连接到存储提供商的连接池超时时间（单位为毫秒）。若不设置超时，请使用`infinity`               | 否   | `5000`     | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                         | 连接池中连接的最大空闲时间（以毫秒为单位）。使用`infinity` 可使连接无限期保持活动状态           | 否   | `infinity` | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                  | 每个连接池的最大连接数                                                | 否   | `500`      | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                 | 要使用的连接池数量                                                  | 否   | 系统调度程序的数量  | `4`                                                           |
| `TUIST_S3_PROTOCOL`                                   | 连接存储提供商时应使用的协议（`http1` 或`http2` ）                          | 否   | `http1`    | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                               | URL 是否应将存储桶名称作为子域名（虚拟主机）来构建                                | 否   | `false`    | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
如果您的存储提供商是 AWS，且希望使用 Web 身份令牌进行身份验证，您可以将环境变量`TUIST_S3_AUTHENTICATION_METHOD`
设置为`aws_web_identity_token_from_env_vars` ，Tuist 将通过常规的 AWS 环境变量使用该方法。
<!-- -->
:::

#### Google Cloud Storage{#google-cloud-storage}
对于 Google Cloud Storage，请按照
[此文档](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)
获取`AWS_ACCESS_KEY_ID` 和`AWS_SECRET_ACCESS_KEY` 这对密钥。`AWS_ENDPOINT`
应设置为`https://storage.googleapis.com` 。其他环境变量与其他符合 S3 标准的存储相同。

### 电子邮件配置{#email-configuration}

Tuist 需要电子邮件功能来实现用户身份验证和事务通知（例如密码重置、账户通知）。目前，**仅支持 Mailgun** 作为电子邮件服务提供商。

| 环境变量                             | 描述                                       | 必需  | 默认值                                  | 示例                     |
| -------------------------------- | ---------------------------------------- | --- | ------------------------------------ | ---------------------- |
| `TUIST_MAILGUN_API_KEY`          | 用于与 Mailgun 进行身份验证的 API 密钥               | 是*  |                                      | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN`           | 发送邮件的域名                                  | 是*  |                                      | `mg.tuist.io`          |
| `TUIST_MAILING_FROM_ADDRESS`     | 将显示在“发件人”字段中的电子邮件地址                      | 是*  |                                      | `noreply@tuist.io`     |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 用户回复的可选回复地址                              | 否   |                                      | `support@tuist.dev`    |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | 跳过新用户注册时的邮箱验证。启用此功能后，用户注册后将自动通过验证，并可立即登录 | 否   | `true` （若未配置电子邮件），`false` （若已配置电子邮件） | `true`,`false`,`1`,`0` |

\* 仅当您需要发送电子邮件时才需配置电子邮件变量。若未配置，系统将自动跳过电子邮件确认步骤

::: info SMTP SUPPORT
<!-- -->
目前尚不提供通用 SMTP 支持。如果您需要为本地部署启用 SMTP 支持，请联系
[contact@tuist.dev](mailto:contact@tuist.dev) 讨论您的具体需求。
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
对于无法访问互联网或未配置电子邮件提供商的本地安装，默认情况下会自动跳过电子邮件确认。用户注册后可立即登录。如果您已配置电子邮件但仍希望跳过确认，请设置`TUIST_SKIP_EMAIL_CONFIRMATION=true`
。若在已配置电子邮件的情况下仍需进行电子邮件确认，请设置`TUIST_SKIP_EMAIL_CONFIRMATION=false` 。
<!-- -->
:::

### Git 平台配置{#git-platform-configuration}

Tuist 可 <LocalizedLink href="/guides/server/authentication">与 Git
平台集成</LocalizedLink>，提供诸如在拉取请求中自动发布评论等额外功能。

#### GitHub{#platform-github}

您需要 [创建一个 GitHub
应用](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。除非您创建的是
OAuth GitHub 应用，否则可以复用之前用于身份验证的应用。在`权限和事件` 的`仓库权限` 部分，您还需要将`拉取请求` 权限设置为`读写` 。

除了`TUIST_GITHUB_APP_CLIENT_ID` 和`TUIST_GITHUB_APP_CLIENT_SECRET` 之外，您还需要以下环境变量：

| 环境变量                           | 描述           | 必需  | 默认值 | 示例                                   |
| ------------------------------ | ------------ | --- | --- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub 应用的私钥 | 是   |     | `-----BEGIN RSA PRIVATE KEY-----...` |

## 本地测试{#testing-locally}

我们提供了一份全面的 Docker Compose 配置文件，其中包含在将 Tuist 服务器部署到基础设施之前，在本地机器上进行测试所需的所有依赖项：

- PostgreSQL 15 搭配 TimescaleDB 2.16 扩展（已弃用）
- ClickHouse 25 用于分析
- ClickHouse Keeper 用于协调
- 适用于 S3 兼容存储的 MinIO
- Redis 用于跨部署的持久化键值存储（可选）
- pgweb 用于数据库管理

::: danger LICENSE REQUIRED
<!-- -->
运行 Tuist 服务器（包括本地开发实例）时，法律要求必须设置有效的`TUIST_LICENSE` 环境变量。如需许可证，请联系
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

**快速入门：**

1. 下载配置文件：
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 配置环境变量：
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE and authentication credentials
   ```

3. 启动所有服务：
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

4. 访问服务器：http://localhost:8080

**服务端点：**
- Tuist 服务器：http://localhost:8080
- MinIO 控制台：http://localhost:9003（凭据：`tuist` /`tuist_dev_password` ）
- MinIO API：http://localhost:9002
- pgweb (PostgreSQL 用户界面)：http://localhost:8081
- Prometheus 指标：http://localhost:9091/metrics
- ClickHouse HTTP：http://localhost:8124

**常用命令：**

检查服务状态：
```bash
docker compose ps
# or: podman compose ps
```

查看日志：
```bash
docker compose logs -f tuist
```

停止服务：
```bash
docker compose down
```

重置所有内容（删除所有数据）：
```bash
docker compose down -v
```

**配置文件：**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 完整的 Docker
  Compose 配置
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse
  配置
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - ClickHouse Keeper 配置
- [.env.example](/server/self-host/.env.example) - 环境变量文件示例

## 部署{#deployment}

官方 Tuist Docker 镜像可在以下地址获取：
```
ghcr.io/tuist/tuist
```

### 拉取 Docker 镜像{#pulling-the-docker-image}

您可以通过执行以下命令获取该图片：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

或拉取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 镜像{#deploying-the-docker-image}

Docker 镜像的部署流程会因您选择的云服务提供商以及贵组织的持续部署策略而有所不同。由于大多数云解决方案和工具（如
[Kubernetes](https://kubernetes.io/)）都将 Docker 镜像作为基本单元，因此本节中的示例应能很好地与您的现有环境相匹配。

:: 警告
<!-- -->
如果您的部署管道需要验证服务器是否正常运行，您可以向`/ready` 发送一个`GET` HTTP 请求，并在响应中验证`200` 状态码。
<!-- -->
:::

#### Fly{#fly}

要在 [Fly](https://fly.io/) 上部署应用，您需要一个`fly.toml` 配置文件。建议在持续部署 (CD)
管道中动态生成该文件。以下是一个供您参考的示例：

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

然后您可以运行`fly launch --local-only --no-deploy` 来启动应用。在后续部署中，请勿运行`fly launch
--local-only` ，而应运行`fly deploy --local-only` 。Fly.io 不允许拉取私有 Docker
镜像，因此我们需要使用`--local-only` 参数。


## Prometheus 指标{#prometheus-metrics}

Tuist 在`/metrics` 处公开 Prometheus 指标，以帮助您监控自托管的实例。这些指标包括：

### Finch HTTP 客户端指标{#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作为其 HTTP 客户端，并提供有关 HTTP
请求的详细指标：

#### 请求指标
- `tuist_prom_ex_finch_request_count_total` - Finch 请求总数（计数器）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 请求时长（直方图）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
  - 时间间隔：10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、2.5秒、5秒、10秒
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 请求异常总数（计数器）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`kind`,`reason`

#### 连接池队列指标
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在连接池队列中等待的时间（直方图）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 时间间隔：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 连接在被使用前处于空闲状态的时间（直方图）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 时间间隔：10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、5秒、10秒
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 队列异常总数（计数器）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`kind`,`reason`

#### 连接指标
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立连接所花费的时间（直方图）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`error`
  - 时间间隔：10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、2.5秒、5秒
- `tuist_prom_ex_finch_connect_count_total` - 连接尝试总数（计数器）
  - 标签：`finch_name`,`scheme`,`host`,`port`

#### 发送指标
- `tuist_prom_ex_finch_send_duration_milliseconds` - 发送请求所花费的时间（直方图）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 时间间隔：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 发送前连接处于空闲状态的时间（直方图）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 时间间隔：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒

所有直方图指标均提供` 、_bucket、` 、` 、_sum、` 以及` 、_count、` 等变体，以供详细分析。

### 其他指标

除了 Finch 指标外，Tuist 还提供了以下指标：
- BEAM 虚拟机性能
- 自定义业务逻辑指标（存储、账户、项目等）
- 数据库性能（使用 Tuist 托管的基础设施时）

## 操作{#operations}

Tuist 在`/ops/` 提供了用于管理实例的一组实用工具。

::: warning Authorization
<!-- -->
只有那些用户名列在`TUIST_OPS_USER_HANDLES` 环境变量中的用户才能访问`/ops/` 端点。
<!-- -->
:::

- **错误（`/ops/errors`）：**
  您可以在此查看应用程序中发生的意外错误。这有助于调试和了解问题原因，如果您遇到问题，我们可能会请您与我们分享这些信息。
- **仪表盘 (`/ops/dashboard`)：**
  您可以查看一个仪表盘，该仪表盘提供有关应用程序性能和健康状况的洞察（例如内存消耗、正在运行的进程、请求数量）。此仪表盘对于了解您使用的硬件是否足以处理当前负载非常有用。
