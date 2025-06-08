---
title: Installation
titleTemplate: :title | On-premise | Server | Tuist
description: Tuist를 인프라에 설치하는 방법을 배워봅니다.
---

# On-premise installation {#onpremise-installation}

인프라에 대한 더 많은 제어를 요구하는 조직을 위해 Tuist 서버의 자체 호스팅 버전을 제공합니다. 이 버전은 Tuist를 자체 인프라에 호스팅하여 사용자의 데이터가 안전하고 비공개로 유지되도록 보장합니다.

> [!IMPORTANT] 기업 고객 전용\
> Tuist의 On-Premise 버전은 Enterprise 플랜을 가입한 조직만 사용 가능합니다. On-Premise 버전에 관심이 있다면, [contact@tuist.dev](mailto:contact@tuist.dev)로 연락 바랍니다.

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

### ClickHouse 데이터베이스 {#clickhouse-database}

대용량 데이터 저장을 위해 [ClickHouse](https://clickhouse.com/)를 사용합니다. 빌드 인사이트와 같은 기능은 ClickHouse가 활성화된 경우에만 동작합니다. ClickHouse는 Timescale Postgres 확장을 대체할 것입니다. ClickHouse를 자체 호스팅을 사용할지 아니면 호스팅 서비스를 이용할지 선택할 수 있습니다.

> [!INFO] MIGRATIONS\
> Docker 이미지의 엔트리포인트는 서비스를 시작하기 전에 자동으로 대기 중인 ClickHouse 스킴 마이그레이션을 실행합니다.

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
> 라이센스는 만료일이 있습니다. 사용자가 서버와 상호 작용하는 Tuist 명령어를 사용할 때, 라이센스가 30일 이내에 만료가 된다면 경고가 표시됩니다. 라이센스를 갱신하고 싶다면, [contact@tuist.dev](mailto:contact@tuist.dev)로 연락 바랍니다.

### 기본 환경 구성 {#base-environment-configuration}

| 환경 변수                          | 설명                                                                    | 필수 여부 | 기본값                                                                                   | 예시                                                                       |                                                                                                                                    |
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

| 환경 변수                           | 설명                                                                                                                                                                                   | 필수 여부 | 기본값    | 예시                                                                     |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----- | ------ | ---------------------------------------------------------------------- |
| `DATABASE_URL`                  | Postgres 데이터베이스 접근을 위한 URL 입니다. URL에는 인증 정보가 포함되어야 합니다.                                                                                              | Yes   |        | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`          | ClickHouse 데이터베이스 접근을 위한 URL URL에는 인증 정보가 포함되어야 합니다.                                                                                                                 | No    |        | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`    | true 이면 데이터베이스에 접속하기 위해 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security)을 사용                                                                                            | No    | `1`    | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`      | 연결 풀에서 유지할 연결 수                                                                                                                                                                      | No    | `10`   | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`   | 풀에서 체크아웃된 모든 연결이 큐 대기 시간보다 더 오래 걸렸는지 확인하는 범위 (밀리초 단위) [(자세한 정보)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | No    | `300`  | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL` | 풀에서 새로운 연결을 끊기위해 필요한 큐에서의 임계 시간 (밀리초 단위) [(자세한 정보)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)              | No    | `1000` | `1000`                                                                 |

### 인증 환경 구성 {#authentication-environment-configuration}

우리는 [아이덴티티 제공자 (IdP)](https://en.wikipedia.org/wiki/Identity_provider) 를 통해 인증을 지원합니다. 이를 활용하려면, 선택한 제공자에 필요한 환경 변수가 서버의 환경에 설정되어 있는지 확인해야 합니다. **누락된 변수**가 있으면 Tuist는 해당 제공자를 건너뜁니다.

#### GitHub {#github}

우리는 [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)을 사용하여 인증하는 것을 권장하지만 [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)을 사용할 수도 있습니다. GitHub에서 지정한 필수 환경 변수를 모두 서버 환경에 포함시켜야 합니다. 변수가 없으면 Tuist는 GitHub 인증을 무시합니다. GitHub 앱을 올바르게 설정하려면 다음과 같습니다:

- GitHub 앱의 일반 설정:
 - `Client ID`를 복사하고 `TUIST_GITHUB_APP_CLIENT_ID`로 설정합니다.
 - 새로운 `client secret`을 생성하고 복사한 다음에 `TUIST_GITHUB_APP_CLIENT_SECRET`로 설정합니다.
 - `Callback URL`을 `http://YOUR_APP_URL/users/auth/github/callback`으로 설정합니다. `YOUR_APP_URL`은 서버의 IP 주소도 사용할 수 있습니다.
- `Permissions and events`의 `Account permissions` 섹션에서 `Email addresses` 권한을 `Read-only`로 설정합니다.

그런 다음, Tuist 서버가 실행되는 환경에서 다음 환경 변수를 노출시킵니다:

| 환경 변수                            | 설명                      | 필수 여부 | 기본값 | 예시                                         |
| -------------------------------- | ----------------------- | ----- | --- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | GitHub 애플리케이션의 클라이언트 ID | Yes   |     | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 애플리케이션의 클라이언트 비밀키       | Yes   |     | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

[OAuth 2](https://developers.google.com/identity/protocols/oauth2)를 사용하여 Google 인증을 설정할 수 있습니다. 이를 위해, OAuth 클라이언트 ID 타입의 새로운 자격 증명을 생성해야 합니다. 자격 증명을 생성할 때, 애플리케이션 타입으로 "Web Application"을 선택하고, 이름을 `Tuist`로 설정하고, 리다이렉트 URI를 호스팅되는 서비스가 실행되는 `base_url`을 활용하여 `{base_url}/users/auth/google/callback`으로 설정합니다. 앱을 생성한 후에 클라이언트 ID와 클라이언트 비밀키를 복사하고 각각 환경 변수 `GOOGLE_CLIENT_ID`와 `GOOGLE_CLIENT_SECRET`로 설정합니다.

> [!NOTE] 동의 화면 범위\
> 동의 화면을 생성해야 할 수도 있습니다. 그렇게 할 때, `userinfo.email`과 `openid` 범위를 추가하고 내부 앱으로 표시해야 합니다.

#### Okta {#okta}

[OAuth 2.0](https://oauth.net/2/) 프로토콜을 통해 Okta 인증을 활성화할 수 있습니다. 다음 구성으로 Okta에서 [앱을 생성](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)해야 합니다:

- **앱 통합 이름:** `Tuist`
- **승인 타입:** 사용자를 대신하여 행동하는 Client에 대해 _Authorization Code_ 활성화
- **로그인 리다이렉트 URL:** 서비스에 접근하는 공개 URL을 `url`라고 하면 `{url}/users/auth/okta/callback`
- **할당:** 이 구성은 보안팀 요구 사항에 따라 달라집니다.

앱이 생성되면, 다음의 환경 변수를 설정해야 합니다:

| 환경 변수                      | 설명                    | 필수 여부 | 기본값 | 예시                          |
| -------------------------- | --------------------- | ----- | --- | --------------------------- |
| `TUIST_OKTA_SITE`          | Okta 조직의 URL          | Yes   |     | `https://your-org.okta.com` |
| `TUIST_OKTA_CLIENT_ID`     | Okta 인증을 위한 클라이언트 ID  | Yes   |     |                             |
| `TUIST_OKTA_CLIENT_SECRET` | Okta 인증을 위한 클라이언트 비밀키 | Yes   |     |                             |

### 저장소 환경 구성 {#storage-environment-configuration}

Tuist는 API를 통해 업로드된 산출물을 저장하기 위한 저장소가 필요합니다. Tuist가 원할하게 동작하려면 **지원되는 저장소 솔루션 중 하나를 구성하는 것이 필수입니다**.

#### S3 호환 저장소 {#s3compliant-storages}

산출물을 저장하기 위해 S3 호환 저장소 제공자를 사용할 수 있습니다. 저장소 제공자와의 인증과 통합 구성을 위해 다음의 환경 변수가 필요합니다:

| 환경 변수                                                | 설명                                                                            | 필수 여부 | 기본값     | 예시                                         |
| ---------------------------------------------------- | ----------------------------------------------------------------------------- | ----- | ------- | ------------------------------------------ |
| `TUIST_ACCESS_KEY_ID` 또는 `AWS_ACCESS_KEY_ID`         | 저장소 제공자 인증을 위한 접근 키 ID                                                        | Yes   |         | `AKIAIOSFOD`                               |
| `TUIST_SECRET_ACCESS_KEY` 또는 `AWS_SECRET_ACCESS_KEY` | 저장소 제공자 인증을 위한 비밀 접근 키                                                        | Yes   |         | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` 또는 `AWS_REGION`                    | 버킷이 위치한 지역                                                                    | Yes   |         | `us-west-2`                                |
| `TUIST_S3_ENDPOINT` 또는 `AWS_ENDPOINT`                | 저장소 제공자의 엔드포인트                                                                | Yes   |         | `https://s3.us-west-2.amazonaws.com`       |
| `TUIST_S3_BUCKET_NAME`                               | 산출물이 저장될 버킷의 이름                                                               | Yes   |         | `tuist-artifacts`                          |
| `TUIST_S3_REQUEST_TIMEOUT`                           | 저장소 제공자 요청에 대한 타임아웃 (초 단위)                                 | No    | `30`    | `30`                                       |
| `TUIST_S3_POOL_TIMEOUT`                              | 저장소 제공자에 대한 연결 풀의 타임아웃 (초 단위)                              | No    | `5`     | `5`                                        |
| `TUIST_S3_POOL_COUNT`                                | 저장소 제공자와의 연결 풀의 수                                                             | No    | `1`     | `1`                                        |
| `TUIST_S3_PROTOCOL`                                  | 저장소 제공자와 연결할 때 사용하는 프로토콜 (`http1` 또는 `http2`)              | No    | `http2` | `http2`                                    |
| `TUIST_S3_VIRTUAL_HOST`                              | URL이 서브도메인 (가상 호스트) 으로 버킷 이름을 구성해야 하는지 여부. | No    | No      | `1`                                        |

> [!NOTE] 환경 변수에서 Web Identity Token을 사용한 AWS 인증\
> 저장소 제공자가 AWS이고 웹 아이덴티티 토큰을 사용하여 인증하려는 경우에 환경 변수 `TUIST_S3_AUTHENTICATION_METHOD`를 `aws_web_identity_token_from_env_vars`로 설정할 수 있습니다. 그러면 Tuist는 기존의 AWS 환경 변수를 사용하여 인증을 진행할 수 있습니다.

#### Google Cloud Storage {#google-cloud-storage}

Google Cloud Storage의 경우, [이 문서](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)를 참고하여 `AWS_ACCESS_KEY_ID`와 `AWS_SECRET_ACCESS_KEY` 쌍을 얻어야 합니다. `AWS_ENDPOINT`는 `https://storage.googleapis.com`으로 설정해야 합니다. 다른 환경 변수는 모든 S3 호환 저장소와 동일합니다.

### Git 플랫폼 구성 {#git-platform-configuration}

Tuist는 Pull Request에 자동으로 댓글을 게시하는 등의 추가 기능을 제공하기 위해 <LocalizedLink href="/server/introduction/integrations#git-platforms">Git 플랫폼과 통합</LocalizedLink>할 수 있습니다.

#### GitHub {#platform-github}

[GitHub 앱을 생성](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)해야 합니다. 인증을 위해 생성한 GitHub 앱을 재사용할 수 있지만, OAuth GitHub 앱을 생성한 경우는 제외입니다. `Permissions and events`의 `Repository permissions` 섹션에서 `Pull requests` 권한을 `Read and write`로 설정해야 합니다.

`TUIST_GITHUB_APP_CLIENT_ID`와 `TUIST_GITHUB_APP_CLIENT_SECRET` 외에도 다음의 환경 변수가 필요합니다:

| 환경 변수                          | 설명                   | 필수 여부 | 기본값 | 예시                                   |
| ------------------------------ | -------------------- | ----- | --- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub 애플리케이션의 비공개 키 | Yes   |     | `-----BEGIN RSA PRIVATE KEY-----...` |

## 배포 {#deployment}

On-premise 사용자는 이미지를 가져올 수 있는 컨테이너 레지스트리를 가지는 [tuist/registry](https://github.com/cloud/registry)에 위치한 리포지토리에 대한 접근 권한을 부여 받습니다. 현재 컨테이너 레지스트리는 개인 사용자에게만 인증을 허용합니다. 따라서 리포지토리 접근 권한이 있는 사용자는 Tuist 조직 내에서 **개인 접근 토큰**을 생성해야 하고 패키지를 읽을 수 있는 권한이 있는지 확인해야 합니다. 제출 하면 우리는 이 토큰을 빠르게 승인할 것입니다.

> [!IMPORTANT] 사용자 토큰 VS 조직 범위 토큰\
> 개인이 기업 조직을 떠난 경우 개인 접근 토큰은 개인과 연결되어 있으므로, 개인 접근 토큰을 사용하는 것이 문제가 될 수 있습니다. GitHub은 이런 문제를 인지하고 있으며, GitHub 앱에서 생성한 토큰을 사용하여 인증할 수 있는 해결책을 적극적으로 개발 중입니다.

### Docker 이미지 가져오기 {#pulling-the-docker-image}

토큰을 생성한 후에 다음 명령어를 실행하여 이미지를 가져올 수 있습니다:

```bash
echo $TOKEN | docker login ghcr.io -u USERNAME --password-stdin
docker pull ghcr.io/tuist/tuist:latest
```

### Docker 이미지 배포 {#deploying-the-docker-image}

Docker 이미지 배포 과정은 선택한 클라우드 제공 업체와 조직의 지속적인 배포 방식에 따라 달라집니다. [Kubernetes](https://kubernetes.io/)와 같은 대부분의 클라우드 솔루션 및 툴은 Docker 이미지를 기본 단위로 사용하므로, 이 섹션의 예시는 기존 설정과 잘 맞습니다.

우리는 **매주 화요일**에 새로운 이미지를 가져와 배포하는 파이프라인을 구축하는 것을 권장합니다. 이렇게 하면 최신 개선 사항을 계속해서 활용할 수 있습니다.

> [!IMPORTANT]
> 배포 파이프라인에서 서버가 정상적으로 동작하는지 확인해야 하는 경우에 `/ready`에 `GET` HTTP 요청을 보내고 응답에서 `200` 코드를 확인할 수 있습니다.

#### Fly {#fly}

앱을 [Fly](https://fly.io/)에 배포하기 위해 `fly.toml` 구성 파일이 필요합니다. Continuous Deployment (CD) 파이프라인 내에서 이 구성 파일을 동적으로 생성하는 것을 고려해야 합니다. 아래는 참고용 예시입니다:

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

이러면 앱을 실행하기 위해 `fly launch --local-only --no-deploy`을 수행할 수 있습니다. 이후 배포에서는 `fly launch --local-only`를 수행하는 대신에 `fly deploy --local-only`를 수행합니다. Fly.io에서는 비공개 Docker 이미지를 가져올 수 없으므로, `--local-only` 플래그를 사용해야 합니다.

### Docker Compose {#docker-compose}

아래는 서비스를 배포하기 위해 참고할 수 있는 `docker-compose.yml` 파일의 예시입니다:

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

Tuist는 인스턴스를 관리하기 위해 사용할 수 있는 유틸리티를 `/ops/`에서 제공합니다.

> [!IMPORTANT] 인증\
> `TUIST_OPS_USER_HANDLES` 환경 변수에 작성된 사용자만 `/ops/` 엔드포인트에 접근할 수 있습니다.

- **오류 (`/ops/errors`):** 애플리케이션에서 발생한 오류를 볼 수 있습니다. 이것은 디버깅과 문제의 원인을 파악하는데 유용하고, 우리는 문제가 발생할 경우 이 정보를 공유해 달라고 요청할 수 있습니다.
- **대시보드 (`/ops/dashboard`):** 애플리케이션의 성능과 상태 (예: 메모리 사용량, 실행 중인 프로세스, 요청 수) 를 확인할 수 있는 대시보드를 볼 수 있습니다. 이 대시보드는 사용 중인 하드웨어가 부하를 처리하기에 충분한지 확인하는데 매우 유용할 수 있습니다.
