---
title: Installation
titleTemplate: :title | On-premise | Server | Tuist
description: Tuist를 인프라에 설치하는 방법을 배워봅니다.
---

# On-premise installation {#onpremise-installation}

인프라에 대한 더 많은 제어를 요구하는 조직을 위해 Tuist 서버의 자체 호스팅 버전을 제공합니다. 이 버전은 Tuist를 자체 인프라에 호스팅하여 사용자의 데이터가 안전하고 비공개로 유지되도록 보장합니다.

> [!IMPORTANT] 기업 고객 전용\
> Tuist의 On-Premise 버전은 Enterprise 플랜을 가입한 조직만 사용 가능합니다. 이 버전에 관심있다면, [contact@tuist.io](mailto:contact@tuist.io)로 연락 바랍니다.

## 출시 주기 {#release-cadence}

Tuist 서버는 **매주 월요일에 출시되며** 버전 이름은 `{MAJOR}.YY.MM.DD` 형식을 따릅니다. 날짜 구성 요소는 호스팅된 버전이 CLI의 출시일로부터 60일 이상 지난 경우, CLI 사용자에게 경고를 보내기 위해 사용됩니다. On-premise 조직은 개발자가 최신 개선 사항의 이점을 누릴 수 있도록 Tuist를 최신으로 유지하는 것이 중요하며, On-premise 설정을 손상시키지 않으면서 더이상 사용하지 않는 기능을 제거할 수 있습니다.

CLI의 주요 구성 요소는 On-premise 사용자와의 조정이 필요한 Tuist 서버에서의 주요 변경 사항을 표시하는데 사용됩니다. 우리가 이것을 사용할 것이라고 기대해서는 안되며 필요한 경우, 전환이 원활하도록 함께 협력할 것입니다.

> [!NOTE] 릴리즈 노트\
> 이미지가 게시되는 레지스트리와 연결된 `tuist/registry` 리포지토리에 연결 권한이 부여됩니다. 모든 릴리즈는 해당 리포지토리의 GitHub 릴리즈에 게시되고 변경 사항은 릴리즈 노트에 포함됩니다.

## 실행 환경 요구 사항 {#runtime-requirements}

이 섹션은 Tuist 서버를 인프라에 호스팅하기 위한 요구 사항을 설명합니다.

### Docker 가상화 이미지 실행 {#running-dockervirtualized-images}

우리는 서버를 [GitHub의 Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)를 통해 [Docker](https://www.docker.com/)로 배포합니다.

실행하기 위해 인프라에서는 Docker 이미지 실행을 지원해야 합니다. 대부분의 인프라는 이것을 지원하는데 이는 운영 환경에서 소프트웨어를 배포하고 실행하는 표준 컨테이너로 자리 잡았기 때문입니다.

### Postgres 데이터베이스 {#postgres-database}

Docker 이미지를 실행하는 것 외에도, 관계형 데이터를 저장하기 위한 [Postgres 데이터베이스](https://www.postgresql.org/)도 필요합니다. 대부분의 인프라는 Postgres 데이터베이스를 포함하여 제공하고 있습니다 (예: [AWS](https://aws.amazon.com/rds/postgresql/) & [Google Cloud](https://cloud.google.com/sql/docs/postgres)).

뛰어난 성능 측정을 위해 우리는 [Timescale Postgres 확장](https://www.timescale.com/)을 사용합니다. Postgres 데이터베이스가 실행되는 머신에 TimescaleDB가 설치되어 있는지 확인해야 합니다. 자세한 설치 방법은 [여기](https://docs.timescale.com/self-hosted/latest/install/)에서 확인할 수 있습니다. Timescale 확장을 설치할 수 없는 경우, Prometheus 메트릭을 사용하여 자체 대시보드를 설정할 수 있습니다.

> [!INFO] 마이그레이션\
> Docker 이미지의 엔트리포인트는 컨테이너가 실행되기 전에 자동으로 대기 중인 스킴 마이그레이션을 실행합니다.

### 저장소 {#storage}

파일 (예: 프레임워크 및 라이브러리 바이너리) 을 저장하기 위한 솔루션도 필요합니다. 현재 S3 호환 저장소를 모두 지원합니다.

## 구성 {#configuration}

서비스의 구성은 실행 시 환경 변수를 통해 이루어집니다. 환경 변수는 민감한 정보이므로, 이를 암호화하여 안전한 비밀번호 관리 솔루션에 저장하길 권장합니다. Tuist는 이러한 변수를 최대한 신중하게 처리하고 로그에 절대로 표시되지 않도록 보장하므로 안심할 수 있습니다.

> [!NOTE] 시작 검증\
> 필요한 변수는 시작할 때 검증됩니다. 필요한 변수가 누락되면 실행이 실패하고 오류 메세지에 누락된 변수가 상세히 표시됩니다.

### 라이센스 구성 {#license-configuration}

On-premise 사용자는 환경 변수로 설정해야 하는 라이센스 키를 받습니다. 이 키는 라이센스를 검증하고 서비스가 계약 조건 내에서 실행되고 있음을 보장합니다.

| 환경 변수           | 설명                                                   | 필수 여부 | 기본값 | 예시       |
| --------------- | ---------------------------------------------------- | ----- | --- | -------- |
| `TUIST_LICENSE` | 서비스 수준 계약 (SLA) 을 체결한 후 제공되는 라이센스 | Yes   |     | `******` |

> [!IMPORTANT] 만료일\
> 라이센스는 만료일이 있습니다. 사용자가 서버와 상호 작용하는 Tuist 명령어를 사용할 때, 라이센스가 30일 이내에 만료가 된다면 경고가 표시됩니다. 라이센스를 갱신하고 싶다면 [contact@tuist.io](mailto:contact@tuist.io)로 연락 바랍니다.

### 기본 환경 구성 {#base-environment-configuration}

| 환경 변수                          | Description                                                           | 필수 여부 | 기본값                                                                                   | 예시                                                                       |                                                                                                                                    |
| ------------------------------ | --------------------------------------------------------------------- | ----- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                | 인터넷에서 인스턴스에 접근하기 위한 기본 URL                                            | Yes   |                                                                                       | https://cloud.tuist.io   |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`        | 정보를 암호화 하는데 사용되는 키 (예: 쿠키에 저장된 세션) | Yes   |                                                                                       |                                                                          | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`    | 해시된 비밀번호를 생성하기 위한 페퍼 (Pepper)                      | No    | $TUIST_SECRET_KEY_BASE |                                                                          |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`      | 랜덤 토큰을 생성하기 위한 비밀 키                                                   | No    | $TUIST_SECRET_KEY_BASE |                                                                          |                                                                                                                                    |
| `TUIST_USE_IPV6`               | `1`로 설정하면 IPv6 주소를 사용해 앱을 구성                                          | No    | `0`                                                                                   | `1`                                                                      |                                                                                                                                    |
| `TUIST_LOG_LEVEL`              | 앱에 사용할 로그 수준                                                          | No    | `info`                                                                                | [Log levels](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | 자동 PR 코멘트 게시와 같은 추가 기능을 활성화하기 위해 GitHub 앱에 사용되는 비공개 키                 | No    | `-----BEGIN RSA...`                                                                   |                                                                          |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`       | 작업 URL에 접근할 수 있는 쉼표로 구분된 사용자 아이디 목록                                   | No    |                                                                                       | `user1,user2`                                                            |                                                                                                                                    |

### 데이터베이스 구성 {#database-configuration}

다음의 환경 변수는 데이터베이스 연결을 구성하기 위해 사용됩니다:

| 환경 변수                           | Description                                                                                                                                                                                                                                                            | 필수 여부 | 기본값    | 예시                                                                     |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- | ------ | ---------------------------------------------------------------------- |
| `DATABASE_URL`                  | The URL to access the Postgres database. Note that the URL should contain the authentication information                                                                                                                                               | Yes   |        | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE`    | When true, it uses [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) to connect to the database                                                                                                                                                            | No    | `1`    | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`      | The number of connections to keep open in the connection pool                                                                                                                                                                                                          | No    | `10`   | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`   | The interval (in miliseconds) for checking if all the connections checked out from the pool took more than the queue interval [(More information)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | No    | `300`  | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL` | The threshold time (in miliseconds) in the queue that the pool uses to determine if it should start dropping new connections [(More information)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)  | No    | `1000` | `1000`                                                                 |

### Authentication environment configuration {#authentication-environment-configuration}

We facilitate authentication through [identity providers (IdP)](https://en.wikipedia.org/wiki/Identity_provider). To utilize this, ensure all necessary environment variables for the chosen provider are present in the server's environment. **Missing variables** will result in Tuist bypassing that provider.

#### GitHub {#github}

We recommend authenticating using a [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) but you can also use the [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app). Make sure to include all essential environment variables specified by GitHub in the server environment. Absent variables will cause Tuist to overlook the GitHub authentication. To properly set up the GitHub app:

- In the GitHub app's general settings:
  - Copy the `Client ID` and set it as `TUIST_GITHUB_APP_CLIENT_ID`
  - Create and copy a new `client secret` and set it as `TUIST_GITHUB_APP_CLIENT_SECRET`
  - Set the `Callback URL` as `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` can also be your server's IP address.
- In the `Permissions and events`'s `Account permissions` section, set the `Email addresses` permission to `Read-only`.

You'll then need to expose the following environment variables in the environment where the Tuist server runs:

| 환경 변수                            | Description                             | 필수 여부 | 기본값 | 예시                                         |
| -------------------------------- | --------------------------------------- | ----- | --- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | The client ID of the GitHub application | Yes   |     | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | The client secret of the application    | Yes   |     | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

You can set up authentication with Google using [OAuth 2](https://developers.google.com/identity/protocols/oauth2). For that, you'll need to create a new credential of type OAuth client ID. When creating the credentials, select "Web Application" as application type, name it `Tuist`, and set the redirect URI to `{base_url}/users/auth/google/callback` where `base_url` is the URL your hosted-service is running at. Once you create the app, copy the client ID and secret and set them as environment variables `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` respectively.

> [!NOTE] CONSENT SCREEN SCOPES
> You might need to create a consent screen. When you do so, make sure to add the `userinfo.email` and `openid` scopes and mark the app as internal.

#### Okta {#okta}

You can enable authentication with Okta through the [OAuth 2.0](https://oauth.net/2/) protocol. You'll have to [create an app](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta) on Okta with the following configuration:

- **App integration name:** `Tuist`
- **Grant type:** Enable _Authorization Code_ for _Client acting on behalf of a user_
- **Sign-in redirect URL:** `{url}/users/auth/okta/callback` where `url` is the public URL your service is accessed through.
- **Assignments:** This configuration will depend on your security team requirements.

Once the app is created you'll need to set the following environment variables:

| 환경 변수                      | Description                                    | 필수 여부 | 기본값 | 예시                          |
| -------------------------- | ---------------------------------------------- | ----- | --- | --------------------------- |
| `TUIST_OKTA_SITE`          | The URL of your Okta organization              | Yes   |     | `https://your-org.okta.com` |
| `TUIST_OKTA_CLIENT_ID`     | The client ID to authenticate against Okta     | Yes   |     |                             |
| `TUIST_OKTA_CLIENT_SECRET` | The client secret to authenticate against Okta | Yes   |     |                             |

### Storage environment configuration {#storage-environment-configuration}

Tuist needs storage to house artifacts uploaded through the API. It's **essential to configure one of the supported storage solutions** for Tuist to operate effectively.

#### S3-compliant storages {#s3compliant-storages}

You can use any S3-compliant storage provider to store artifacts. The following environment variables are required to authenticate and configure the integration with the storage provider:

| 환경 변수                                                | Description                                                                                         | 필수 여부 | 기본값     | 예시                                         |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ----- | ------- | ------------------------------------------ |
| `TUIST_ACCESS_KEY_ID` or `AWS_ACCESS_KEY_ID`         | The access key ID to authenticate against the storage provider                                      | Yes   |         | `AKIAIOSFOD`                               |
| `TUIST_SECRET_ACCESS_KEY` or `AWS_SECRET_ACCESS_KEY` | The secret access key to authenticate against the storage provider                                  | Yes   |         | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` or `AWS_REGION`                    | The region where the bucket is located                                                              | Yes   |         | `us-west-2`                                |
| `TUIST_S3_ENDPOINT` or `AWS_ENDPOINT`                | The endpoint of the storage provider                                                                | Yes   |         | `https://s3.us-west-2.amazonaws.com`       |
| `TUIST_S3_BUCKET_NAME`                               | The name of the bucket where the artifacts will be stored                                           | Yes   |         | `tuist-artifacts`                          |
| `TUIST_S3_REQUEST_TIMEOUT`                           | The timeout (in seconds) for requests to the storage provider                    | No    | `30`    | `30`                                       |
| `TUIST_S3_POOL_TIMEOUT`                              | The timeout (in seconds) for the connection pool to the storage provider         | No    | `5`     | `5`                                        |
| `TUIST_S3_POOL_COUNT`                                | The number of pools to use for connections to the storage provider                                  | No    | `1`     | `1`                                        |
| `TUIST_S3_PROTOCOL`                                  | The protocol to use when connecting to the storage provider (`http1` or `http2`) | No    | `http2` | `http2`                                    |

> [!NOTE] AWS authentication with Web Identity Token from environment variables
> If your storage provider is AWS and you'd like to authenticate using a web identity token, you can set the environment variable `TUIST_S3_AUTHENTICATION_METHOD` to `aws_web_identity_token_from_env_vars`, and Tuist will use that method using the conventional AWS environment variables.

#### Google Cloud Storage {#google-cloud-storage}

For Google Cloud Storage, follow [these docs](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) to get the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` pair. The `AWS_ENDPOINT` should be set to `https://storage.googleapis.com`. Other environment variables are the same as for any other S3-compliant storage.

### Git platform configuration {#git-platform-configuration}

Tuist can <LocalizedLink href="/server/introduction/integrations#git-platforms">integrate with Git platforms</LocalizedLink> to provide extra features such as automatically posting comments in your pull requests.

#### GitHub {#platform-github}

You will need to [create a GitHub app](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps). You can reuse the one you created for authentication, unless you created an OAuth GitHub app. In the `Permissions and events`'s `Repository permissions` section, you will need to additionally set the `Pull requests` permission to `Read and write`.

On top of the `TUIST_GITHUB_APP_CLIENT_ID` and `TUIST_GITHUB_APP_CLIENT_SECRET`, you will need the following environment variables:

| 환경 변수                          | Description                               | 필수 여부 | 기본값 | 예시                                   |
| ------------------------------ | ----------------------------------------- | ----- | --- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | The private key of the GitHub application | Yes   |     | `-----BEGIN RSA PRIVATE KEY-----...` |

## Deployment {#deployment}

On-premise users are granted access to the repository located at [tuist/registry](https://github.com/cloud/registry) which has a linked container registry for pulling images. Currently, the container registry allows authentication only as an individual user. Therefore, users with repository access must generate a **personal access token** within the Tuist organization, ensuring they have the necessary permissions to read packages. After submission, we will promptly approve this token.

> [!IMPORTANT] USER VS ORGANIZATION-SCOPED TOKENS
> Using a personal access token presents a challenge because it's associated with an individual who might eventually depart from the enterprise organization. GitHub recognizes this limitation and is actively developing a solution to allow GitHub apps to authenticate with app-generated tokens.

### Pulling the Docker image {#pulling-the-docker-image}

After generating the token, you can retrieve the image by executing the following command:

```bash
echo $TOKEN | docker login ghcr.io -u USERNAME --password-stdin
docker pull ghcr.io/tuist/tuist:latest
```

### Deploying the Docker image {#deploying-the-docker-image}

The deployment process for the Docker image will differ based on your chosen cloud provider and your organization's continuous deployment approach. Since most cloud solutions and tools, like [Kubernetes](https://kubernetes.io/), utilize Docker images as fundamental units, the examples in this section should align well with your existing setup.

We recommend establishing a deployment pipeline that that runs **every Tuesday**, pulling and deploying fresh images. This ensures you consistently benefit from the latest improvements.

> [!IMPORTANT]
> If your deployment pipeline needs to validate that the server is up and running, you can send a `GET` HTTP request to `/ready` and assert a `200` status code in the response.

#### Fly {#fly}

To deploy the app on [Fly](https://fly.io/), you'll require a `fly.toml` configuration file. Consider generating it dynamically within your Continuous Deployment (CD) pipeline. Below is a reference example for your use:

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

Then you can run `fly launch --local-only --no-deploy` to launch the app. On subsequent deploys, instead of running `fly launch --local-only`, you will need to run `fly deploy --local-only`. Fly.io doesn't allow to pull private Docker images, which is why we need to use the `--local-only` flag.

### Docker Compose {#docker-compose}

Below is an example of a `docker-compose.yml` file that you can use as a reference to deploy the service:

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

## Operations {#operations}

Tuist provides a set of utilities under `/ops/` that you can use to manage your instance.

> [!IMPORTANT] Authorization
> Only people whose handles are listed in the `TUIST_OPS_USER_HANDLES` environment variable can access the `/ops/` endpoints.

- **Errors (`/ops/errors`):** You can view unexpected errors that ocurred in the application. This is useful for debugging and understanding what went wrong and we might ask you to share this information with us if you're facing issues.
- **Dashboard (`/ops/dashboard`):** You can view a dashboard that provides insights into the application's performance and health (e.g. memory consumption, processes running, number of requests). This dashboard can be quite useful to understand if the hardware you're using is enough to handle the load.
