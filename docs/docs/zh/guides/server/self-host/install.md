---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# 自主机安装 {#self-host-installation}

我们为需要对基础设施进行更多控制的组织提供自助托管版 Tuist 服务器。该版本允许您在自己的基础设施上托管 Tuist，确保您的数据安全私密。

> [重要] 需要许可证 自助托管 Tuist 需要合法有效的付费许可证。企业版 Tuist 仅适用于企业计划。如果您对该版本感兴趣，请联系
> [contact@tuist.dev](mailto:contact@tuist.dev)。

## 释放节奏 {#release-cadence}

我们会根据 Main 上可发布的新变更，不断发布 Tuist
的新版本。我们遵循[语义版本](https://semver.org/)，以确保可预测的版本和兼容性。

主要组件用于标记 Tuist 服务器中需要与内部用户协调的破坏性更改。您不要指望我们会使用它，如果我们需要，请放心，我们会与您合作，使过渡顺利进行。

## 持续部署 {#continuous-deployment}

我们强烈建议设置持续部署管道，每天自动部署最新版本的 Tuist。这将确保您始终可以访问最新功能、改进和安全更新。

下面是一个 GitHub 操作工作流程示例，每天检查并部署新版本：

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

## 运行时要求 {#runtime-requirements}

本节概述了在您的基础设施上托管 Tuist 服务器的要求。

### 运行 Docker 虚拟化镜像 {#running-dockervirtualized-images}

我们通过[GitHub
的容器注册中心](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)将服务器作为[Docker](https://www.docker.com/)镜像发布。

要运行它，你的基础架构必须支持运行 Docker 映像。请注意，大多数基础设施提供商都支持 Docker，因为它已成为在生产环境中分发和运行软件的标准容器。

### Postgres 数据库 {#postgres-database}

除了运行 Docker 映像，您还需要一个 [Postgres
数据库](https://www.postgresql.org/)来存储关系型数据。大多数基础设施提供商都提供 Posgres
数据库（例如，[AWS](https://aws.amazon.com/rds/postgresql/) 和 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)）。

为了进行高效分析，我们使用了[Timescale Postgres 扩展](https://www.timescale.com/)。你需要确保运行
Postgres 数据库的机器上安装了
TimescaleDB。请按照安装说明[此处](https://docs.timescale.com/self-hosted/latest/install/)了解更多信息。如果无法安装
Timescale 扩展，可以使用 Prometheus 指标设置自己的仪表板。

> [！INFO] 迁移 Docker 映像的入口点会在启动服务前自动运行任何待处理的模式迁移。

### ClickHouse 数据库 {#clickhouse-database}

为了存储大量数据，我们使用了 [ClickHouse](https://clickhouse.com/)。某些功能，如构建洞察力，只有在启用
ClickHouse 后才能使用。ClickHouse 最终将取代 Timescale Postgres 扩展。你可以选择自行托管 ClickHouse
或使用其托管服务。

> [！INFO] 迁移 Docker 映像的入口点会在启动服务前自动运行任何待定的 ClickHouse 模式迁移。

### 存储 {#storage}

您还需要一个存储文件（如框架和库二进制文件）的解决方案。目前，我们支持任何符合 S3 标准的存储。

## 配置 {#configuration}

服务配置在运行时通过环境变量完成。鉴于这些变量的敏感性，我们建议将其加密并存储在安全的密码管理解决方案中。请放心，Tuist
会谨慎处理这些变量，确保它们不会显示在日志中。

> [注意] 启动校验 启动时将对必要的变量进行校验。如果缺少任何变量，启动将失败，错误信息将详细说明缺少的变量。

### 许可证配置 {#license-configuration}

作为内部用户，您会收到一个许可证密钥，您需要将其作为环境变量公开。该密钥用于验证许可证，确保服务在协议条款范围内运行。

| 环境变量                               | 说明                                                                                                             | 需要  | 默认值 | 示例                                        |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------- | --- | --- | ----------------------------------------- |
| `TUIST_LICENSE`                    | 签署服务级别协议后提供的许可证                                                                                                | 是*  |     | `******`                                  |
| `tuist_license_certificate_base64` | **是 `TUIST_LICENSE`** 的绝佳替代品。Base64 编码的公共证书，用于在服务器无法与外部服务联系的 air-gapped 环境中进行离线许可证验证。仅在`TUIST_LICENSE` 无法使用时使用 | 是*  |     | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

* 必须提供`TUIST_LICENSE` 或`TUIST_LICENSE_CERTIFICATE_BASE64`
，但不能同时提供。标准部署使用`TUIST_LICENSE` 。

> [重要] 过期日期 许可证有到期日期。如果许可证过期不到 30 天，用户在使用与服务器交互的 Tuist 命令时将收到警告。如果您有兴趣更新许可证，请联系
> [contact@tuist.dev](mailto:contact@tuist.dev)。

### 基本环境配置 {#base-environment-configuration}

| 环境变量                                  | 说明                                                                   | 需要  | 默认值                                | 示例                                                                  |                                                                                                                                    |
| ------------------------------------- | -------------------------------------------------------------------- | --- | ---------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | 从互联网访问实例的基本 URL                                                      | 是   |                                    | https://tuist.dev                                                   |                                                                                                                                    |
| `tuist_secret_key_base`               | 用于加密信息（如 cookie 中的会话信息）的密钥                                           | 是   |                                    |                                                                     | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `tuist_secret_key_password`           | Pepper 生成散列密码                                                        | 没有  | `$tuist_secret_key_base`           |                                                                     |                                                                                                                                    |
| `tuist_secret_key_tokens`             | 用于生成随机令牌的密匙                                                          | 没有  | `$tuist_secret_key_base`           |                                                                     |                                                                                                                                    |
| `tuist_secret_key_encryption`         | 32 字节密钥，用于对敏感数据进行 AES-GCM 加密                                         | 没有  | `$tuist_secret_key_base`           |                                                                     |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | 当`1` 时，它会将应用程序配置为使用 IPv6 地址                                          | 没有  | `0`                                | `1`                                                                 |                                                                                                                                    |
| `tuist_log_level`                     | 应用程序使用的日志级别                                                          | 没有  | `信息`                               | [日志级别](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels)。 |                                                                                                                                    |
| `tuist_github_app_private_key_base64` | 用于 GitHub 应用程序的 base64 编码私钥，用于解锁额外功能，如发布自动 PR 评论                     | 没有  | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                     |                                                                                                                                    |
| `tuist_github_app_private_key`        | GitHub 应用程序用于解锁额外功能（如发布自动 PR 评论）的私钥。**建议使用 base64 编码版本，以避免出现特殊字符问题** | 没有  | `-----BEGIN RSA...`                |                                                                     |                                                                                                                                    |
| `tuist_ops_user_handles`              | 以逗号分隔的用户句柄列表，可访问操作 URL                                               | 没有  |                                    | `用户1,用户2`                                                           |                                                                                                                                    |
| `TUIST_WEB`                           | 启用网络服务器端点                                                            | 没有  | `1`                                | `1` 或`0`                                                            |                                                                                                                                    |

### 数据库配置 {#database-configuration}

以下环境变量用于配置数据库连接：

| 环境变量                                 | 说明                                                                                                                               | 需要  | 默认值       | 示例                                                                     |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | 访问 Postgres 数据库的 URL。请注意，URL 应包含身份验证信息                                                                                           | 是   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `tuist_clickhouse_url`               | 访问 ClickHouse 数据库的 URL。请注意，URL 应包含验证信息                                                                                           | 没有  |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `tuist_use_ssl_for_database`         | 为真时，使用 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) 连接数据库                                                       | 没有  | `1`       | `1`                                                                    |
| `tuist_database_pool_size`           | 连接池中保持开放的连接数                                                                                                                     | 没有  | `10`      | `10`                                                                   |
| `tuist_database_queue_target`        | 检查从连接池中签出的所有连接所用时间是否超过队列时间间隔的时间间隔（以毫秒为单位）[（更多信息）](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)。 | 没有  | `300`     | `300`                                                                  |
| `tuist_database_queue_interval`      | 队列中的阈值时间（以毫秒为单位），用于判断池是否应该开始丢弃新连接 [ (更多信息)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)。       | 没有  | `1000`    | `1000`                                                                 |
| `tuist_clickhouse_flush_interval_ms` | 以毫秒为单位的 ClickHouse 缓冲区刷新时间间隔                                                                                                     | 没有  | `5000`    | `5000`                                                                 |
| `tuist_clickhouse_max_buffer_size`   | 强制刷新前 ClickHouse 缓冲区的最大字节数                                                                                                       | 没有  | `1000000` | `1000000`                                                              |
| `tuist_clickhouse_buffer_pool_size`  | 运行的 ClickHouse 缓冲进程数量                                                                                                            | 没有  | `5`       | `5`                                                                    |

### 身份验证环境配置 {#authentication-environment-configuration}

我们通过[身份提供商（IdP）](https://en.wikipedia.org/wiki/Identity_provider)为身份验证提供便利。要利用这一点，请确保服务器环境中存在所选提供商的所有必要环境变量。**缺少变量**
将导致 Tuist 绕过该提供商。

#### GitHub {#github}

我们建议使用 [GitHub
应用程序](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)，但也可以使用
[OAuth
应用程序](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)。确保服务器环境中包含
GitHub 指定的所有重要环境变量。缺少变量会导致 Tuist 忽略 GitHub 认证。正确设置 GitHub 应用程序：
- 在 GitHub 应用程序的常规设置中：
    - 复制`客户端 ID` 并将其设置为`TUIST_GITHUB_APP_CLIENT_ID`
    - 创建并复制一个新的`客户秘密` ，并将其设置为`TUIST_GITHUB_APP_CLIENT_SECRET`
    - 将`回调 URL` 设置为`http://YOUR_APP_URL/users/auth/github/callback`
      。`YOUR_APP_URL` 也可以是服务器的 IP 地址。
- 需要以下权限
  - 资料库：
    - 拉取请求：读写
  - 账户
    - 电子邮件地址：只读

在`Permissions and events` 的`Account permissions` 部分，将`Email addresses`
权限设置为`Read-only` 。

然后，您需要在 Tuist 服务器运行的环境中公开以下环境变量：

| 环境变量                             | 说明                 | 需要  | 默认值 | 示例                                         |
| -------------------------------- | ------------------ | --- | --- | ------------------------------------------ |
| `tuist_github_app_client_id`     | GitHub 应用程序的客户端 ID | 是   |     | `Iv1.a629723000043722`                     |
| `tuist_github_app_client_secret` | 应用程序的客户秘密          | 是   |     | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### 谷歌 {#google｝

您可以使用 [OAuth 2](https://developers.google.com/identity/protocols/oauth2) 与
Google 进行身份验证。为此，你需要创建一个 OAuth 客户端 ID 类型的新凭证。创建凭证时，选择 "Web 应用程序
"作为应用程序类型，将其命名为`Tuist` ，并将重定向 URI 设置为`{base_url}/users/auth/google/callback`
，其中`base_url` 是您的托管服务运行的 URL。创建应用程序后，复制客户端 ID 和秘密，并将其分别设置为环境变量`GOOGLE_CLIENT_ID`
和`GOOGLE_CLIENT_SECRET` 。

> [您可能需要创建一个同意屏幕。创建时，请确保添加`userinfo.email` 和`openid` 作用域，并将应用程序标记为内部应用程序。

#### Okta {#okta}

您可以通过 [OAuth 2.0](https://oauth.net/2/) 协议启用 Okta
身份验证。您必须按照<LocalizedLink href="/guides/integrations/sso#okta">以下说明</LocalizedLink>在
Okta
上[创建一个应用程序](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)。

在设置 Okta 应用程序时获得客户端 ID 和密码后，您需要设置以下环境变量：

| 环境变量                         | 说明                               | 需要  | 默认值 | 示例  |
| ---------------------------- | -------------------------------- | --- | --- | --- |
| `tuist_okta_1_client_id`     | 与 Okta 进行身份验证的客户 ID。该数字应为您的组织 ID | 是   |     |     |
| `tuist_okta_1_client_secret` | 对 Okta 进行身份验证的客户端密文              | 是   |     |     |

`1` 需要用您的机构 ID 代替。通常是 1，但请在您的数据库中查看。

### 存储环境配置 {#storage-environment-configuration}

Tuist 需要存储空间来存放通过 API 上传的工件。**必须配置一个受支持的存储解决方案** ，Tuist 才能有效运行。

#### 符合 S3 标准的存储设备 {#s3compliant-storages}

您可以使用任何符合 S3 标准的存储提供程序来存储人工制品。需要使用以下环境变量来验证和配置与存储提供商的集成：

| 环境变量                                               | 说明                                          | 需要  | 默认值     | 示例                                         |
| -------------------------------------------------- | ------------------------------------------- | --- | ------- | ------------------------------------------ |
| `TUIST_ACCESS_KEY_ID` 或`AWS_ACCESS_KEY_ID`         | 对存储提供商进行身份验证的访问密钥 ID                        | 是   |         | `AKIAIOSFOD`                               |
| `TUIST_SECRET_ACCESS_KEY` 或`AWS_SECRET_ACCESS_KEY` | 用于对存储提供商进行身份验证的秘密访问密钥                       | 是   |         | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 或`AWS_REGION`                    | 水桶所在的区域                                     | 没有  | `汽车`    | `us-west-2`                                |
| `TUIST_S3_ENDPOINT` 或`AWS_ENDPOINT`                | 存储提供程序的端点                                   | 是   |         | `https://s3.us-west-2.amazonaws.com`       |
| `tuist_s3_bucket_name`                             | 存储人工制品的存储桶名称                                | 是   |         | `tuist-artifacts`                          |
| `tuist_s3_connect_timeout`                         | 与存储提供程序建立连接的超时（以毫秒为单位                       | 没有  | `3000`  | `3000`                                     |
| `tuist_s3_receive_timeout`                         | 从存储提供程序接收数据的超时（以毫秒为单位                       | 没有  | `5000`  | `5000`                                     |
| `tuist_s3_pool_timeout`                            | 存储提供商连接池的超时（毫秒）。使用`infinity` 表示无超时          | 没有  | `5000`  | `5000`                                     |
| `tuist_s3_pool_max_idle_time`                      | 池中连接的最长空闲时间（毫秒）。使用`infinity` 可使连接无限期地保持激活状态 | 没有  | `淼`     | `60000`                                    |
| `tuist_s3_pool_size`                               | 每个连接池的最大连接数                                 | 没有  | `500`   | `500`                                      |
| `tuist_s3_pool_count`                              | 要使用的连接池数量                                   | 没有  | 系统调度员数量 | `4`                                        |
| `tuist_s3_protocol`                                | 连接存储提供商时使用的协议（`http1` 或`http2`)             | 没有  | `http1` | `http1`                                    |
| `tuist_s3_virtual_host`                            | 是否应将邮筒名称作为子域（虚拟主机）来构建 URL                   | 没有  | `错误`    | `1`                                        |

> [！注意] 通过环境变量使用网络身份令牌进行 AWS 身份验证 如果您的存储提供商是
> AWS，并且您希望使用网络身份令牌进行身份验证，您可以将环境变量`TUIST_S3_AUTHENTICATION_METHOD`
> 设置为`aws_web_identity_token_from_env_vars` ，Tuist 将使用传统的 AWS 环境变量使用该方法。

#### 谷歌云存储 {#google-cloud-storage｝
对于 Google Cloud
Storage，请按照[这些文档](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)获取`AWS_ACCESS_KEY_ID`
和`AWS_SECRET_ACCESS_KEY` 对。`AWS_ENDPOINT` 应设置为`https://storage.googleapis.com`
。其他环境变量与任何其他 S3 兼容存储相同。

### Git 平台配置 {#git-platform-configuration}

Tuist 可以<LocalizedLink href="/guides/server/authentication">与 Git
平台</LocalizedLink>集成，提供额外功能，例如自动在拉取请求中发布注释。

#### GitHub {#platform-github}

您需要[创建一个 GitHub
应用程序](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)。除非你创建了一个
OAuth GitHub 应用程序，否则你可以重复使用已创建的应用程序进行身份验证。在`Permissions and events` 的`Repository
permissions` 部分，你还需要将`Pull requests` 权限设置为`Read and write` 。

除了`TUIST_GITHUB_APP_CLIENT_ID` 和`TUIST_GITHUB_APP_CLIENT_SECRET` 之外，还需要以下环境变量：

| 环境变量                           | 说明             | 需要  | 默认值 | 示例                                   |
| ------------------------------ | -------------- | --- | --- | ------------------------------------ |
| `tuist_github_app_private_key` | GitHub 应用程序的私钥 | 是   |     | `-----begin rsa private key-----...` |

## 部署 {#deployment｝

Tuist 官方 Docker 映像可在以下网址获取：
```
ghcr.io/tuist/tuist
```

### 拉取 Docker 映像 {#pulling-the-docker-image}

执行以下命令即可获取图像：

```bash
docker pull ghcr.io/tuist/tuist:latest
```

或调出特定版本：
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### 部署 Docker 映像 {#deploying-the-docker-image}

Docker 映像的部署流程将根据您选择的云提供商和组织的持续部署方法而有所不同。由于大多数云解决方案和工具（如
[Kubernetes](https://kubernetes.io/)）都使用 Docker 映像作为基本单元，因此本节中的示例应与您的现有设置保持一致。

> [！重要] 如果部署管道需要验证服务器是否正常运行，可向`/ready` 发送`GET` HTTP 请求，并在响应中断言`200` 状态代码。

#### 飞 {#fly｝

要在 [Fly](https://fly.io/) 上部署应用程序，您需要`fly.toml` 配置文件。请考虑在持续部署 (CD)
管道中动态生成该文件。以下是供您使用的参考示例：

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

然后，您可以运行`fly launch --local-only --no-deploy` 来启动应用程序。在后续部署中，你需要运行`fly deploy
--local-only` ，而不是运行`fly launch --local-only` 。Fly.io 不允许拉取私有的 Docker
镜像，因此我们需要使用`--local-only` 标志。

### Docker Compose {#docker-compose}

下面是`docker-compose.yml` 文件的示例，你可以把它作为部署服务的参考：

```yaml
version: '3.8'
services:
  db:
    image: timescale/timescaledb-ha:pg16
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - PGDATA=/var/lib/postgresql/data/pgdata
    ports:
      - '5432:5432'
    volumes:
      - db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  pgweb:
    container_name: pgweb
    restart: always
    image: sosedoff/pgweb
    ports:
      - "8081:8081"
    links:
      - db:db
    environment:
      PGWEB_DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
    depends_on:
      - db

  tuist:
    image: ghcr.io/tuist/tuist:latest
    container_name: tuist
    depends_on:
      - db
    ports:
      - "80:80"
      - "8080:8080"
      - "443:443"
    expose:
      - "80"
      - "8080"
      - "443:443"
    environment:
      # Base Tuist Env - https://docs.tuist.io/en/guides/dashboard/on-premise/install#base-environment-configuration
      TUIST_USE_SSL_FOR_DATABASE: "0"
      TUIST_LICENSE:  # ...
      DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
      TUIST_APP_URL: https://localhost:8080
      TUIST_SECRET_KEY_BASE: # ...
      WEB_CONCURRENCY: 80

      # Auth - one method
      # GitHub Auth - https://docs.tuist.io/en/guides/dashboard/on-premise/install#github
      TUIST_GITHUB_OAUTH_ID:
      TUIST_GITHUB_APP_CLIENT_SECRET:

      # Okta Auth - https://docs.tuist.io/en/guides/dashboard/on-premise/install#okta
      TUIST_OKTA_SITE:
      TUIST_OKTA_CLIENT_ID:
      TUIST_OKTA_CLIENT_SECRET:
      TUIST_OKTA_AUTHORIZE_URL: # Optional
      TUIST_OKTA_TOKEN_URL: # Optional
      TUIST_OKTA_USER_INFO_URL: # Optional
      TUIST_OKTA_EVENT_HOOK_SECRET: # Optional

      # Storage
      AWS_ACCESS_KEY_ID: # ...
      AWS_SECRET_ACCESS_KEY: # ...
      AWS_S3_REGION: # ...
      AWS_ENDPOINT: # https://amazonaws.com
      TUIST_S3_BUCKET_NAME: # ...

      # Other

volumes:
  db:
    driver: local
```

## 普罗米修斯度量标准 {#prometheus-metrics}

Tuist 在`/metrics` 公开 Prometheus 指标，帮助您监控自托管实例。这些指标包括

### Finch HTTP 客户端指标 {#finch-metrics}

Tuist 使用 [Finch](https://github.com/sneako/finch) 作为 HTTP 客户端，并提供有关 HTTP
请求的详细指标：

#### 要求指标
- `tuist_prom_ex_finch_request_count_total` - Finch 请求总数（计数器）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 请求的持续时间（柱状图）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`status`
  - 桶10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、2.5秒、5秒、10秒
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 异常请求总数（计数器）。
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`kind`,`reason`

#### 连接池队列指标
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 在连接池队列中等待的时间（柱状图）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 桶1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 连接被使用前的空闲时间（柱状图）。
  - 标签：`finch_name`,`scheme`,`host`,`port`,`pool`
  - 桶10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、5秒、10秒
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 队列异常总数（计数器）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`kind`,`reason`

#### 连接指标
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 建立连接所用的时间（直方图）
  - 标签：`finch_name`,`scheme`,`host`,`port`,`error`
  - 桶10毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒、2.5秒、5秒
- `tuist_prom_ex_finch_connect_count_total` - 尝试连接的总次数（计数器）。
  - 标签：`finch_name`,`scheme`,`host`,`port`

#### 发送指标
- `tuist_prom_ex_finch_send_duration_milliseconds` - 发送请求所用的时间（直方图）
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 桶1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒、1秒
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 发送前连接空闲的时间（直方图）。
  - 标签：`finch_name`,`method`,`scheme`,`host`,`port`,`error`
  - 桶1毫秒、5毫秒、10毫秒、25毫秒、50毫秒、100毫秒、250毫秒、500毫秒

所有直方图指标都提供`_bucket` 、`_sum` 和`_count` 变体，以便进行详细分析。

### 其他指标

除 Finch 指标外，Tuist 还提供以下指标：
- BEAM 虚拟机性能
- 自定义业务逻辑指标（存储、账户、项目等）
- 数据库性能（使用 Tuist 托管基础设施时）

## 操作 {# 操作｝

Tuist 在`/ops/` 下提供了一套实用程序，可用于管理实例。

> [重要] 授权 只有手柄列在`TUIST_OPS_USER_HANDLES` 环境变量中的用户才能访问`/ops/` 端点。

- **错误 (`/ops/errors`)：**
  您可以查看应用程序中出现的意外错误。这对于调试和了解出错原因非常有用，如果您遇到问题，我们可能会要求您与我们分享这些信息。
- **仪表盘（`/ops/dashboard`）：**
  您可以查看仪表盘，了解应用程序的性能和健康状况（如内存消耗、正在运行的进程、请求数）。该仪表盘对于了解所使用的硬件是否足以处理负载非常有用。
