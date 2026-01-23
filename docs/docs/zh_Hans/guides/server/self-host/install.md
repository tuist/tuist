---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# 自主托管安装{#self-host-installation}

我们为需要更强基础设施控制权的组织提供自托管版Tuist服务器。此版本允许您在自有基础设施上部署Tuist，确保数据安全与隐私。

::: warning LICENSE REQUIRED
<!-- -->
自托管 Tuist 需持有合法有效的付费许可证。Tuist 本地部署版本仅面向企业版客户开放。如需获取该版本，请联系
[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

## 发布节奏{#release-cadence}

当主分支出现可发布的新变更时，我们会持续发布 Tuist
的新版本。我们遵循[语义化版本控制规范](https://semver.org/)，以确保版本迭代的可预测性和兼容性。

主要组件用于标记Tuist服务器中需要与本地用户协调的重大变更。您不应预期我们会使用该组件，若确有需要，请放心我们将与您协作确保过渡顺畅。

## 持续部署{#continuous-deployment}

我们强烈建议设置持续部署管道，实现Tuist最新版本的每日自动部署。这将确保您始终能使用最新功能、改进内容及安全更新。

以下是一个每日检查并部署新版本的GitHub Actions工作流示例：

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

## 运行时要求{#runtime-requirements}

本节概述了在您的基础设施上托管 Tuist 服务器的技术要求。

### 兼容性矩阵{#compatibility-matrix}

Tuist服务器已通过测试，兼容以下最低版本：

| 组件          | 最低版本   | 注释                     |
| ----------- | ------ | ---------------------- |
| PostgreSQL  | 15     | 使用 TimescaleDB 扩展      |
| TimescaleDB | 2.16.1 | 必需的 PostgreSQL 扩展（已弃用） |
| ClickHouse  | 25     | 分析所需                   |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB 目前是 Tuist 服务器必需的 PostgreSQL 扩展，用于时间序列数据存储与查询。但根据**TimescaleDB 已被弃用**
，随着我们将所有时间序列功能迁移至 ClickHouse，该扩展将在近期从必需依赖项中移除。当前请确保您的 PostgreSQL 实例已安装并启用
TimescaleDB。
<!-- -->
:::

### 运行 Docker 虚拟化镜像{#running-dockervirtualized-images}

我们通过[GitHub容器注册表](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)以[Docker](https://www.docker.com/)镜像形式分发该服务器。

要运行该程序，您的基础设施必须支持运行 Docker 镜像。请注意，由于 Docker
已成为生产环境中分发和运行软件的标准容器，大多数基础设施提供商都支持此功能。

### Postgres数据库{#postgres-database}

除运行 Docker 镜像外，您还需要一个搭载 [TimescaleDB 扩展](https://www.timescale.com/) 的 [Postgres
数据库](https://www.postgresql.org/) 来存储关系型和时间序列数据。多数基础设施提供商均在其服务中包含 Postgres
数据库（例如 [AWS](https://aws.amazon.com/rds/postgresql/) 与 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)）。

**TimescaleDB扩展要求：**
Tuist需使用TimescaleDB扩展实现高效的时间序列数据存储与查询。该扩展用于命令事件、分析及其他时间相关功能。运行Tuist前请确保您的PostgreSQL实例已安装并启用TimescaleDB。

::: info MIGRATIONS
<!-- -->
Docker镜像的入口点会在启动服务前自动运行所有待处理的模式迁移。若因缺少TimescaleDB扩展导致迁移失败，需先在数据库中安装该扩展。
<!-- -->
:::

### ClickHouse数据库{#clickhouse-database}

Tuist使用[ClickHouse](https://clickhouse.com/)存储和查询海量分析数据。ClickHouse是**构建洞察等功能所需的**
，并将作为我们逐步淘汰TimescaleDB后的主要时间序列数据库。您可选择自主部署ClickHouse或使用其托管服务。

::: info MIGRATIONS
<!-- -->
Docker镜像的入口点会在启动服务前自动执行任何待处理的ClickHouse模式迁移。
<!-- -->
:::

### 存储{#storage}

您还需要一个存储文件的解决方案（例如框架和库的二进制文件）。目前我们支持任何符合S3标准的存储方案。

::: tip OPTIMIZED CACHING
<!-- -->
若您的主要目标是自建存储二进制文件的桶并降低缓存延迟，则无需完全自托管整个服务器。可自托管缓存节点，并将它们连接至托管的Tuist服务器或您自托管的服务器。

参见<LocalizedLink href="/guides/cache/self-host">缓存自托管指南</LocalizedLink>。
<!-- -->
:::

## 配置 {#configuration}

服务配置通过运行时环境变量完成。鉴于这些变量的敏感性，建议将其加密并存储于安全的密码管理解决方案中。请放心，Tuist会以最高标准处理这些变量，确保它们绝不会出现在日志中。

::: info LAUNCH CHECKS
<!-- -->
启动时将验证必要变量。若存在缺失变量，程序将启动失败，错误信息将详细说明缺失的变量。
<!-- -->
:::

### 许可证配置{#license-configuration}

作为本地部署用户，您将收到需作为环境变量设置的许可证密钥。该密钥用于验证许可证有效性，确保服务在协议条款范围内运行。

| 环境变量                               | 描述                                                                                                   | 必需  | 默认值 | 示例                                        |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------- | --- | --- | ----------------------------------------- |
| `TUIST_LICENSE`                    | 签署服务级别协议后提供的许可                                                                                       | 是*  |     | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **`TUIST_LICENSE` 的特殊替代方案** 。用于离线许可证验证的Base64编码公钥证书，适用于服务器无法连接外部服务的物理隔离环境。仅当`TUIST_LICENSE` 无法使用时采用。 | 是*  |     | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* 必须提供以下任一选项：`TUIST_LICENSE` 或`TUIST_LICENSE_CERTIFICATE_BASE64`
，但不可同时使用。标准部署请使用`TUIST_LICENSE` 。

::: warning EXPIRATION DATE
<!-- -->
许可证设有有效期。若许可证剩余有效期不足30天，用户在使用与服务器交互的Tuist命令时将收到警告。如需续订许可证，请联系[contact@tuist.dev](mailto:contact@tuist.dev)。
<!-- -->
:::

### 基础环境配置{#base-environment-configuration}

| 环境变量                                  | 描述                                                         | 必需  | 默认值                                | 示例                                                                 |                                                                                                                                    |
| ------------------------------------- | ---------------------------------------------------------- | --- | ---------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | 从互联网访问实例的基础URL                                             | 是   |                                    | https://tuist.dev                                                  |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | 用于加密信息（例如Cookie中的会话数据）的密钥                                  | 是   |                                    |                                                                    | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Pepper用于生成哈希密码                                             | 不   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | 生成随机令牌的密钥                                                  | 不   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | 用于AES-GCM加密敏感数据的32字节密钥                                     | 不   | `$TUIST_SECRET_KEY_BASE`           |                                                                    |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | 当`1` 时，该配置将使应用程序使用 IPv6 地址                                 | 不   | `0`                                | `1`                                                                |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | 应用程序应使用的日志级别                                               | 不   | `info`                             | [日志级别](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | GitHub 应用名称的 URL 版本                                        | 不   |                                    | `my-app`                                                           |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | 用于GitHub应用解锁额外功能（如自动发布PR评论）的base64编码私钥                     | 不   | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                    |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | 用于GitHub应用解锁额外功能（如自动发布PR评论）的私钥。**建议使用base64编码版本以避免特殊字符问题** | 不   | `-----BEGIN RSA...`                |                                                                    |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | 以逗号分隔的用户名列表，这些用户拥有操作URL的访问权限                               | 不   |                                    | `user1,user2`                                                      |                                                                                                                                    |
| `TUIST_WEB`                           | 启用Web服务器端点                                                 | 不   | `1`                                | `1` 或`0`                                                           |                                                                                                                                    |

### 数据库配置{#database-configuration}

以下环境变量用于配置数据库连接：

| 环境变量                                 | 描述                                                                                                                        | 必需  | 默认值       | 示例                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | 访问 Postgres 数据库的 URL。请注意 URL 应包含身份验证信息                                                                                    | 是   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | 访问ClickHouse数据库的URL。请注意URL应包含身份验证信息                                                                                       | 不   |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | 当为真时，使用[SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security)连接数据库                                                 | 不   | `1`       | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | 连接池中需保持打开的连接数                                                                                                             | 不   | `10`      | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | 检查从连接池中提取的所有连接是否超过队列间隔的时间间隔（以毫秒为单位）[(更多信息)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 不   | `300`     | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | 队列中用于判断是否开始丢弃新连接的阈值时间（单位：毫秒）[(更多信息)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)        | 不   | `1000`    | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse缓冲区刷新间隔（毫秒）                                                                                                     | 不   | `5000`    | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | 强制刷新前的ClickHouse缓冲区最大字节数                                                                                                  | 不   | `1000000` | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | 要运行的ClickHouse缓冲区进程数量                                                                                                     | 不   | `5`       | `5`                                                                    |

### 身份验证环境配置{#authentication-environment-configuration}

我们通过[身份提供商(IdP)](https://en.wikipedia.org/wiki/Identity_provider)实现身份验证。使用时请确保服务器环境中已配置所选提供商所需的所有环境变量。**若缺少**
变量，Tuist将跳过该提供商。

#### GitHub{#github}

我们建议使用[GitHub应用](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)进行身份验证，但您也可以使用[OAuth应用](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。请确保在服务器环境中包含GitHub指定的所有必要环境变量。缺少变量将导致Tuist忽略GitHub身份验证。正确配置GitHub应用的方法如下：
- 在 GitHub 应用的常规设置中：
    - 复制`客户端ID` 并将其设置为`TUIST_GITHUB_APP_CLIENT_ID`
    - 创建并复制新的`客户端密钥` ，将其设置为`TUIST_GITHUB_APP_CLIENT_SECRET`
    - 设置`回调网址` 为`http://YOUR_APP_URL/users/auth/github/callback` 。`应用网址`
      也可使用服务器IP地址。
- 需要以下权限：
  - 仓库：
    - 拉取请求：阅读与撰写
  - 账户：
    - 电子邮件地址：只读

在`权限和事件` 的`账户权限` 部分，将`电子邮件地址` 权限设置为`只读` 。

随后需在 Tuist 服务器运行环境中暴露以下环境变量：

| 环境变量                             | 描述                 | 必需  | 默认值 | 示例                                         |
| -------------------------------- | ------------------ | --- | --- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | GitHub 应用程序的客户端 ID | 是   |     | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 应用程序的客户端密钥         | 是   |     | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google{#google}

可通过[OAuth
2](https://developers.google.com/identity/protocols/oauth2)设置Google认证。为此需创建OAuth客户端ID类型的凭证。创建凭证时，请选择"Web应用程序"作为应用类型，命名为`Tuist`
，并将重定向URI设置为`{base_url}/users/auth/google/callback` ，其中`base_url` 即您托管服务运行的URL。
创建应用后，复制客户端ID和密钥，并将其分别设置为环境变量：`GOOGLE_CLIENT_ID` ` GOOGLE_CLIENT_SECRET`

::: info CONSENT SCREEN SCOPES
<!-- -->
您可能需要创建同意屏幕。操作时请确保添加以下范围：`（用户信息邮箱）` 和`（开放ID）` ，并将应用标记为内部应用。
<!-- -->
:::

#### Okta{#okta}

您可通过[OAuth
2.0](https://oauth.net/2/)协议启用Okta身份验证。需遵循<LocalizedLink href="/guides/integrations/sso#okta">此指引</LocalizedLink>在Okta上[创建应用程序](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在完成Okta应用程序设置并获取客户端ID和密钥后，您需要设置以下环境变量：

| 环境变量                         | 描述                              | 必需  | 默认值 | 示例  |
| ---------------------------- | ------------------------------- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID`     | 用于在Okta进行身份验证的客户端ID。该数字应为您的组织ID | 是   |     |     |
| `TUIST_OKTA_1_CLIENT_SECRET` | 用于对 Okta 进行身份验证的客户端密钥           | 是   |     |     |

`1` 中的数字需替换为贵机构的ID。通常为1，但请在数据库中核对确认。

### 存储环境配置{#storage-environment-configuration}

Tuist需要存储空间来存放通过API上传的文物。为确保Tuist高效运行，必须配置支持的存储方案之一（详见：**** ）。

#### 符合S3标准的存储设备{#s3compliant-storages}

可使用任何符合S3标准的存储服务商存储工件。需配置以下环境变量以完成身份验证及存储服务商集成设置：

| 环境变量                                                  | 描述                                                   | 必需  | 默认值        | 示例                                                            |
| ----------------------------------------------------- | ---------------------------------------------------- | --- | ---------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` 或`AWS_ACCESS_KEY_ID`         | 用于向存储提供商进行身份验证的访问密钥ID                                | 是   |            | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` 或`AWS_SECRET_ACCESS_KEY` | 用于向存储提供商进行身份验证的密钥                                    | 是   |            | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` 或`AWS_REGION`                       | 桶所在的区域                                               | 不   | `auto`     | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` 或`AWS_ENDPOINT`                   | 存储提供商的终点                                             | 是   |            | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                | 存储工件的存储桶名称                                           | 是   |            | `tuist-artifacts`                                             |
| `TUIST_S3_CA_CERT_PEM`                                | 用于验证S3 HTTPS连接的PEM编码CA证书。适用于采用自签名证书或内部证书颁发机构的物理隔离环境。 | 不   | 系统CA捆绑包    | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                            | 连接存储提供商的超时时间（单位：毫秒）                                  | 不   | `3000`     | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                            | 从存储提供商接收数据的超时时间（单位：毫秒）                               | 不   | `5000`     | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                               | 存储提供程序连接池的超时时间（单位：毫秒）。使用`infinity` 表示无超时限制           | 不   | `5000`     | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                         | 连接池中连接的最大空闲时间（单位：毫秒）。使用`infinity` 可使连接无限期保持活动状态      | 不   | `infinity` | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                  | 每个连接池的最大连接数                                          | 不   | `500`      | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                 | 要使用的连接池数量                                            | 不   | 系统调度程序数量   | `4`                                                           |
| `TUIST_S3_PROTOCOL`                                   | 连接存储提供商时使用的协议（`http1` 或`http2` ）                     | 不   | `http1`    | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                               | URL 是否应使用存储桶名称作为子域名（虚拟主机）进行构建                        | 不   | `false`    | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
若您的存储提供商为AWS且希望使用Web身份令牌进行认证，可将环境变量`设置为TUIST_S3_AUTHENTICATION_METHOD，将`
设置为`，并通过aws_web_identity_token_from_env_vars` 调用，Tuist将通过常规AWS环境变量采用该认证方式。
<!-- -->
:::

#### Google 云存储{#google-cloud-storage}
对于Google云存储，请遵循[此文档](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)获取`AWS_ACCESS_KEY_ID`
及`AWS_SECRET_ACCESS_KEY` 密钥对。`AWS_ENDPOINT` 应设置为`https://storage.googleapis.com`
。其他环境变量与任何其他S3兼容存储相同。

### 邮件配置{#email-configuration}

Tuist需要电子邮件功能用于用户认证和交易通知（例如密码重置、账户通知）。目前仅支持**作为邮件服务提供商** 。

| 环境变量                             | 描述                                | 必需  | 默认值                          | 示例                     |
| -------------------------------- | --------------------------------- | --- | ---------------------------- | ---------------------- |
| `TUIST_MAILGUN_API_KEY`          | 用于与Mailgun进行身份验证的API密钥            | 是*  |                              | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN`           | 邮件发送源域名                           | 是*  |                              | `mg.tuist.io`          |
| `TUIST_MAILING_FROM_ADDRESS`     | 将显示在"发件人"字段中的电子邮件地址               | 是*  |                              | `noreply@tuist.io`     |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 用户回复的可选回复地址                       | 不   |                              | `support@tuist.dev`    |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | 跳过新用户注册的邮箱确认。启用后，用户注册后将自动确认并可立即登录 | 不   | `true` 若未配置邮件，`false` 若已配置邮件 | `true`,`false`,`1`,`0` |

\* 仅当需要发送邮件时才需配置邮件参数。若未配置，系统将自动跳过邮件确认环节

::: info SMTP SUPPORT
<!-- -->
当前暂不支持通用SMTP功能。若需为本地部署配置SMTP支持，请联系[contact@tuist.dev](mailto:contact@tuist.dev)讨论具体需求。
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
对于无网络连接或未配置邮件服务商的本地部署环境，系统默认跳过邮件确认流程。用户注册后可立即登录。若已配置邮件服务但仍需跳过确认，请设置：`TUIST_SKIP_EMAIL_CONFIRMATION=true`
若需在邮件配置完成后强制执行确认，请设置：`TUIST_SKIP_EMAIL_CONFIRMATION=false`
<!-- -->
:::

### Git平台配置{#git-platform-configuration}

Tuist 可 <LocalizedLink href="/guides/server/authentication">集成 Git
平台</LocalizedLink>，提供额外功能，例如在拉取请求中自动发布评论。

#### GitHub{#platform-github}

您需要[创建一个GitHub应用程序](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。若您创建的是OAuth
GitHub应用程序，则可复用认证时创建的应用；在`的权限与事件` 中，需在`的仓库权限` 部分，额外将`的拉取请求权限` 设置为`读写权限` 。

除`TUIST_GITHUB_APP_CLIENT_ID` 和`TUIST_GITHUB_APP_CLIENT_SECRET` 外，您还需要以下环境变量：

| 环境变量                           | 描述             | 必需  | 默认值 | 示例                                   |
| ------------------------------ | -------------- | --- | --- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub 应用程序的私钥 | 是   |     | `-----BEGIN RSA PRIVATE KEY-----...` |

## 本地测试{#testing-locally}

我们提供完整的 Docker Compose 配置文件，包含在基础设施部署前于本地测试 Tuist 服务器所需的所有依赖项：

- PostgreSQL 15 搭配 TimescaleDB 2.16 扩展（已弃用）
- ClickHouse 25 用于分析
- ClickHouse Keeper 用于协调
- MinIO 用于 S3 兼容存储
- Redis用于跨部署的持久化键值存储（可选）
- pgweb 用于数据库管理

::: danger LICENSE REQUIRED
<!-- -->
运行Tuist服务器（包括本地开发实例）时，法律要求必须设置有效的环境变量：`TUIST_LICENSE`
。如需许可证，请联系[contact@tuist.dev](mailto:contact@tuist.dev)。
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

4. 访问服务器地址：http://localhost:8080

**服务端点：**
- Tuist 服务器：http://localhost:8080
- MinIO控制台：http://localhost:9003（凭证：`tuist` /`tuist_dev_password` ）
- MinIO API：http://localhost:9002
- pgweb (PostgreSQL 用户界面)：http://localhost:8081
- 普罗米修斯指标：http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**常用指令：**

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
  Compose 配置文件
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse
  配置文件
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - ClickHouse Keeper 配置文件
- [.env.example](/server/self-host/.env.example) - 示例环境变量文件

## 部署{#deployment}

官方 Tuist Docker 镜像可通过以下地址获取：
```
ghcr.io/tuist/tuist
```

### 拉取 Docker 镜像{#pulling-the-docker-image}

执行以下命令即可获取图片：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

或提取特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 镜像{#deploying-the-docker-image}

Docker镜像的部署流程将因您选择的云服务提供商及组织的持续部署策略而异。鉴于多数云解决方案和工具（如[Kubernetes](https://kubernetes.io/)）均以Docker镜像作为基础单元，本节示例应能与您的现有架构良好兼容。

:: 警告
<!-- -->
若部署管道需验证服务器是否正常运行，可向`/ready` 发送`GET` HTTP 请求，并在响应中确认`200` 状态码。
<!-- -->
:::

#### Fly{#fly}

要在[Fly](https://fly.io/)上部署应用，您需要`的fly.toml`
配置文件。建议在持续部署(CD)管道中动态生成该文件。以下是供您参考的示例：

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

随后可执行`fly launch --local-only --no-deploy` 启动应用。后续部署时，请勿运行`fly launch
--local-only` ，而需执行`fly deploy --local-only`
。因Fly.io禁止拉取私有Docker镜像，故需使用`--local-only` 参数。


## 普罗米修斯指标{#prometheus-metrics}

Tuist通过`/metrics和` 暴露Prometheus指标，助您监控自托管实例。这些指标包括：

### Finch HTTP 客户端指标{#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作为其 HTTP 客户端，并公开有关 HTTP
请求的详细指标：

#### 请求指标
- `tuist_prom_ex_finch_request_count_total` - Finch请求总数（计数器）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP请求持续时间（直方图）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
  - 时间段：10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、2.5秒、5秒、10秒
- `tuist_prom_ex_finch_request_exception_count_total` - Finch请求异常总数（计数器）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`kind`,`reason`

#### 连接池队列指标
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在连接池队列中等待的时间（直方图）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 桶：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 记录连接在被使用前处于空闲状态的时间（直方图）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 时间段：10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、5秒、10秒
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch队列异常总数（计数器）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`kind`,`reason`

#### 连接指标
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立连接所耗时间（直方图）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`error`
  - 桶：10毫秒，50毫秒，100毫秒，250毫秒，500毫秒，1秒，2.5秒，5秒
- `tuist_prom_ex_finch_connect_count_total` - 总连接尝试次数（计数器）
  - 标签：`finch_name`,`scheme`,`host`,`port`

#### 发送指标
- `tuist_prom_ex_finch_send_duration_milliseconds` - 发送请求所耗时间（直方图）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 桶：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 发送前连接空闲时间统计（直方图）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 桶：1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒

所有直方图指标均提供以下变体以供详细分析：`_bucket` ` _sum` ` _count`

### 其他指标

除Finch指标外，Tuist还提供以下指标：
- BEAM虚拟机性能
- 自定义业务逻辑指标（存储、账户、项目等）
- 数据库性能（使用Tuist托管基础设施时）

## 操作{#operations}

Tuist 在`/ops/` 提供了一组实用工具，可用于管理您的实例。

::: warning Authorization
<!-- -->
仅当用户名出现在环境变量`TUIST_OPS_USER_HANDLES` 中时，才可访问`/ops/` 接口。
<!-- -->
:::

- **错误（`/ops/errors`）：** 可查看应用程序中发生的意外错误。此功能有助于调试和理解问题根源，若您遇到故障，我们可能会要求您提供此信息。
- **控制面板（`/ops/dashboard`）：**
  您可查看该控制面板，它能提供应用程序性能与健康状况的洞察（例如内存消耗、运行进程、请求数量）。此面板对于判断当前硬件是否足以处理负载非常有用。
