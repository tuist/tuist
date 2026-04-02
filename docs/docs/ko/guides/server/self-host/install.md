---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# 자체 호스팅 설치 {#self-host-installation}

인프라에 대한 더 많은 제어권이 필요한 조직을 위해 Tuist 서버의 자체 호스팅 버전을 제공합니다. 이 버전을 사용하면 자체 인프라에서
Tuist를 호스팅할 수 있어 데이터의 보안과 비공개성을 보장할 수 있습니다.

::: warning LICENSE REQUIRED
<!-- -->
Tuist를 자체 호스팅하려면 법적으로 유효한 유료 라이선스가 필요합니다. Tuist 온프레미스 버전은 엔터프라이즈 플랜을 이용하는 조직에만
제공됩니다. 이 버전에 관심이 있으시면 [contact@tuist.dev](mailto:contact@tuist.dev)으로 문의해 주십시오.
<!-- -->
:::

## 릴리스 주기 {#release-cadence}

Tuist는 메인 브랜치에 출시 가능한 변경 사항이 반영되는 대로 지속적으로 새 버전을 출시합니다. 예측 가능한 버전 관리와 호환성을 보장하기
위해 [시맨틱 버저닝](https://semver.org/)을 따릅니다.

이 주요 구성 요소는 온프레미스 사용자와의 조정이 필요한 Tuist 서버의 중대한 변경 사항을 표시하는 데 사용됩니다. 당사가 이를 사용할
것이라고 기대하지 마십시오. 만약 필요한 경우, 원활한 전환을 위해 귀사와 협력할 것이니 안심하십시오.

## 지속적 배포 {#continuous-deployment}

매일 Tuist의 최신 버전을 자동으로 배포하는 지속적 배포 파이프라인을 설정할 것을 강력히 권장합니다. 이를 통해 항상 최신 기능, 개선 사항
및 보안 업데이트를 이용할 수 있습니다.

다음은 매일 새 버전을 확인하고 배포하는 GitHub Actions 워크플로 예시입니다:

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

## 실행 환경 요구 사항 {#runtime-requirements}

이 섹션에서는 사용자의 인프라에서 Tuist 서버를 호스팅하기 위한 요구 사항을 설명합니다.

### 호환성 매트릭스 {#compatibility-matrix}

Tuist 서버는 다음의 최소 버전과 호환되는 것으로 테스트되었습니다:

| 구성 요소       | 최소 버전  | 참고 사항                        |
| ----------- | ------ | ---------------------------- |
| PostgreSQL  | 15     | TimescaleDB 확장 기능 사용 시       |
| TimescaleDB | 2.16.1 | 필수 PostgreSQL 확장 기능 (사용 중단됨) |
| ClickHouse  | 25     | 분석에 필수                       |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB는 현재 Tuist 서버에 필수적인 PostgreSQL 확장 기능으로, 시계열 데이터 저장 및 쿼리에 사용됩니다. 그러나
**TimescaleDB는 더 이상 권장되지 않으며(** ), 모든 시계열 기능을 ClickHouse로 마이그레이션함에 따라 가까운 시일 내에
필수 의존성에서 제외될 예정입니다. 당분간은 PostgreSQL 인스턴스에 TimescaleDB가 설치되어 있고 활성화되어 있는지 확인하십시오.
<!-- -->
:::

### Docker 가상화 이미지 실행 {#running-dockervirtualized-images}

저희는 [GitHub 컨테이너
레지스트리](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)를
통해 이 서버를 [Docker](https://www.docker.com/) 이미지로 배포합니다.

이 기능을 실행하려면 인프라가 Docker 이미지 실행을 지원해야 합니다. Docker는 프로덕션 환경에서 소프트웨어를 배포하고 실행하는 표준
컨테이너로 자리 잡았기 때문에 대부분의 인프라 제공업체에서 이를 지원합니다.

### Postgres 데이터베이스 {#postgres-database}

Docker 이미지를 실행하는 것 외에도, 관계형 데이터와 시계열 데이터를 저장하려면 [TimescaleDB 확장
기능](https://www.timescale.com/)이 포함된 [Postgres
데이터베이스](https://www.postgresql.org/)가 필요합니다. 대부분의 인프라 제공업체는 서비스에 Postgres
데이터베이스를 포함하고 있습니다(예: [AWS](https://aws.amazon.com/rds/postgresql/) 및 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)).

**TimescaleDB 확장 기능 필수:** Tuist는 효율적인 시계열 데이터 저장 및 쿼리를 위해 TimescaleDB 확장 기능이
필요합니다. 이 확장 기능은 명령 이벤트, 분석 및 기타 시간 기반 기능에 사용됩니다. Tuist를 실행하기 전에 PostgreSQL 인스턴스에
TimescaleDB가 설치되어 있고 활성화되어 있는지 확인하십시오.

::: info MIGRATIONS
<!-- -->
Docker 이미지의 엔트리포인트는 서비스를 시작하기 전에 대기 중인 스키마 마이그레이션을 자동으로 실행합니다. TimescaleDB 확장
프로그램이 없어 마이그레이션이 실패하는 경우, 먼저 데이터베이스에 해당 확장 프로그램을 설치해야 합니다.
<!-- -->
:::

### ClickHouse 데이터베이스 {#clickhouse-database}

Tuist는 대량의 분석 데이터를 저장하고 쿼리하기 위해 [ClickHouse](https://clickhouse.com/)를 사용합니다.
ClickHouse는 인사이트 구축과 같은 기능에 **** 필요하며, 향후 타임스케일DB를 단계적으로 폐지함에 따라 기본 시계열 데이터베이스가
될 것입니다. ClickHouse를 자체 호스팅할지 아니면 호스팅된 서비스를 사용할지 선택할 수 있습니다.

::: info MIGRATIONS
<!-- -->
Docker 이미지의 엔트리포인트는 서비스를 시작하기 전에 보류 중인 ClickHouse 스키마 마이그레이션을 자동으로 실행합니다.
<!-- -->
:::

### 저장 {#storage}

또한 파일(예: 프레임워크 및 라이브러리 바이너리)을 저장할 수 있는 솔루션이 필요합니다. 현재 S3 호환 저장소라면 어떤 것이든 지원합니다.

::: tip OPTIMIZED CACHING
<!-- -->
주로 바이너리 파일을 저장할 자체 저장소를 마련하고 캐시 지연 시간을 줄이는 것이 목적이라면, 서버 전체를 직접 호스팅할 필요는 없을 수
있습니다. 캐시 노드만 직접 호스팅하여 호스팅된 Tuist 서버나 직접 호스팅하는 서버에 연결할 수 있습니다.

<LocalizedLink href="/guides/cache/self-host">캐시 자체 호스팅 가이드</LocalizedLink>를
참조하십시오.
<!-- -->
:::

## 환경 설정 {#configuration}

서비스 구성은 런타임 시 환경 변수를 통해 이루어집니다. 이러한 변수의 민감한 특성을 고려하여, 암호화된 형태로 안전한 비밀번호 관리 솔루션에
저장할 것을 권장합니다. Tuist는 이러한 변수를 극도로 신중하게 처리하며, 로그에 절대 표시되지 않도록 보장하므로 안심하셔도 됩니다.

::: info LAUNCH CHECKS
<!-- -->
필요한 변수들은 시작 시점에 확인됩니다. 누락된 변수가 있으면 실행이 실패하며, 오류 메시지에 누락된 변수가 상세히 표시됩니다.
<!-- -->
:::

### 라이선스 구성 {#license-configuration}

온프레미스 사용자는 환경 변수로 설정해야 하는 라이선스 키를 받게 됩니다. 이 키는 라이선스를 확인하고 서비스가 계약 조건에 따라 실행되고
있는지 확인하는 데 사용됩니다.

| 환경 변수                              | 설명                                                                                                                                                      | 필수  | 기본 값 | 예                                         |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | --- | ---- | ----------------------------------------- |
| `TUIST_LICENSE`                    | 서비스 수준 계약서(SLA) 체결 후 제공되는 라이선스                                                                                                                          | 예*  |      | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **`TUIST_LICENSE`의 예외적인 대안**. 서버가 외부 서비스에 접속할 수 없는 에어갭(air-gapped) 환경에서 오프라인 라이선스 검증을 위한 Base64 인코딩된 공개 인증서입니다. `TUIST_LICENSE` 를 사용할 수 없는 경우에만 사용하십시오. | 예*  |      | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* `TUIST_LICENSE` 또는 `TUIST_LICENSE_CERTIFICATE_BASE64` 중 하나만 제공해야 하며, 둘 다
제공해서는 안 됩니다. 표준 배포의 경우 `TUIST_LICENSE` 를 사용하십시오.

::: warning EXPIRATION DATE
<!-- -->
라이선스에는 만료일이 있습니다. 라이선스 만료일까지 30일 미만이 남은 경우, 서버와 연동되는 Tuist 명령어를 사용할 때 사용자에게 경고
메시지가 표시됩니다. 라이선스 갱신에 관심이 있으시면 [contact@tuist.dev](mailto:contact@tuist.dev)으로
문의해 주십시오.
<!-- -->
:::

### 기본 환경 설정 {#base-environment-configuration}

| 환경 변수                                 | 설명                                                                                                             | 필수  | 기본 값                               | 예                                                                   |                                                                                                                                    |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------- | --- | ---------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | 인터넷에서 인스턴스에 접속하기 위한 기본 URL                                                                                     | 예   |                                    | https://tuist.dev                                                   |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | 정보(예: 쿠키 내 세션)를 암호화하는 데 사용하는 키                                                                                 | 예   |                                    |                                                                     | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | Pepper를 사용하여 해시된 비밀번호 생성                                                                                       | 아니요 | `$TUIST_SECRET_KEY_BASE`           |                                                                     |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | 무작위 토큰 생성을 위한 비밀 키                                                                                             | 아니요 | `$TUIST_SECRET_KEY_BASE`           |                                                                     |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | 민감한 데이터의 AES-GCM 암호화를 위한 32바이트 키                                                                               | 아니요 | `$TUIST_SECRET_KEY_BASE`           |                                                                     |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | `1` 을 실행하면 앱이 IPv6 주소를 사용하도록 설정됩니다                                                                             | 아니요 | `0`                                | `1`                                                                 |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | 앱에 사용할 로그 수준                                                                                                   | 아니요 | `정보`                               | [로그 수준](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | GitHub 앱 이름의 URL 버전                                                                                            | 아니요 |                                    | `my-app`                                                            |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 앱에서 자동 PR 댓글 작성과 같은 추가 기능을 활성화하는 데 사용되는 base64 인코딩된 개인 키                                                | 아니요 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                     |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | GitHub 앱에서 자동 PR 댓글 작성과 같은 추가 기능을 활성화하는 데 사용되는 개인 키입니다. **특수 문자로 인한 문제를 방지하려면 base64로 인코딩된 버전을 사용하는 것이 좋습니다.** | 아니요 | `-----BEGIN RSA...`                |                                                                     |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | 작업 URL에 액세스 권한이 있는 사용자 핸들의 쉼표로 구분된 목록                                                                          | 아니요 |                                    | `user1,user2`                                                       |                                                                                                                                    |
| `TUIST_WEB`                           | 웹 서버 엔드포인트 활성화                                                                                                 | 아니요 | `1`                                | `1` 또는 `0`                                                          |                                                                                                                                    |

### 데이터베이스 구성 {#database-configuration}

다음 환경 변수들은 데이터베이스 연결을 구성하는 데 사용됩니다:

| 환경 변수                                | 설명                                                                                                                                             | 필수  | 기본 값      | 예                                                                      |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | Postgres 데이터베이스에 접속하는 URL입니다. URL에는 인증 정보가 포함되어야 합니다.                                                                                          | 예   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | ClickHouse 데이터베이스에 접속하는 URL입니다. URL에는 인증 정보가 포함되어야 합니다.                                                                                        | 아니요 |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | true인 경우, [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security)을 사용하여 데이터베이스에 연결합니다                                                    | 아니요 | `1`       | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | 연결 풀에서 유지할 연결 수                                                                                                                                | 아니요 | `10`      | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | 풀에서 체크아웃된 모든 연결이 큐 간격보다 오래 걸렸는지 확인하는 간격(밀리초 단위) [(자세한 정보)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)       | 아니요 | `300`     | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | 풀이 새 연결을 끊기 시작해야 할지 여부를 결정하는 데 사용하는 큐의 임계값 시간(밀리초 단위) [(자세한 정보)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 아니요 | `1000`    | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 버퍼 플러시 간격(밀리초 단위)                                                                                                                   | 아니요 | `5000`    | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | 플러시를 강제하기 전까지 허용되는 ClickHouse 버퍼의 최대 크기(바이트 단위)                                                                                                | 아니요 | `1000000` | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | 실행할 ClickHouse 버퍼 프로세스 수                                                                                                                       | 아니요 | `5`       | `5`                                                                    |

### 인증 환경 구성 {#authentication-environment-configuration}

당사는 [ID 제공자(IdP)](https://en.wikipedia.org/wiki/Identity_provider)를 통해 인증을
지원합니다. 이를 이용하려면 선택한 제공자에 필요한 모든 환경 변수가 서버 환경에 설정되어 있는지 확인하십시오. **** 변수가 누락된 경우
Tuist는 해당 제공자를 우회합니다.

#### GitHub {#github}

[GitHub
앱](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)을
사용하여 인증하는 것을 권장하지만, [OAuth
앱](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)을
사용할 수도 있습니다. 서버 환경에 GitHub에서 지정한 모든 필수 환경 변수를 포함해야 합니다. 변수가 누락되면 Tuist가 GitHub
인증을 인식하지 못합니다. GitHub 앱을 올바르게 설정하려면:
- GitHub 앱의 일반 설정에서:
    - `의 클라이언트 ID` 를 복사하여 `의 TUIST_GITHUB_APP_CLIENT_ID로 설정하십시오.`
    - `의 새 클라이언트 시크릿을 생성하여 복사하고(` ), 이를 `TUIST_GITHUB_APP_CLIENT_SECRET로
      설정하십시오.`
    - `콜백 URL` 을 `http://YOUR_APP_URL/users/auth/github/callback` `
      YOUR_APP_URL로 설정하십시오.` 은 서버의 IP 주소일 수도 있습니다.
- 다음 권한이 필요합니다:
  - 저장소:
    - 풀 리퀘스트: 읽기 및 쓰기
  - 계정:
    - 이메일 주소: 읽기 전용

` `` `의 '권한 및 이벤트(Permissions and events)' 페이지 내 '계정 권한(Account permissions)'
섹션에서 '이메일 주소(Email addresses)' 권한을 '읽기 전용(Read-only)' 으로 설정하십시오.` ```

그런 다음 Tuist 서버가 실행되는 환경에서 다음 환경 변수를 노출해야 합니다:

| 환경 변수                            | 설명                      | 필수  | 기본 값 | 예                                          |
| -------------------------------- | ----------------------- | --- | ---- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | GitHub 애플리케이션의 클라이언트 ID | 예   |      | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 애플리케이션의 클라이언트 시크릿       | 예   |      | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

[OAuth 2](https://developers.google.com/identity/protocols/oauth2)를 사용하여 Google
인증을 설정할 수 있습니다. 이를 위해 OAuth 클라이언트 ID 유형의 새 자격 증명을 생성해야 합니다. 자격 증명을 생성할 때 애플리케이션
유형으로 "웹 애플리케이션"을 선택하고, 이름을 `Tuist` 로 지정한 다음, 리디렉션 URI를
`{base_url}/users/auth/google/callback` 로 설정하세요. 여기서 `base_url` 은 호스팅 서비스가 실행 중인
URL입니다. 앱을 생성한 후, 클라이언트 ID와 시크릿을 복사하여 각각 환경 변수 `GOOGLE_CLIENT_ID` 및
`GOOGLE_CLIENT_SECRET` 로 설정하십시오.

::: info CONSENT SCREEN SCOPES
<!-- -->
동의 화면을 생성해야 할 수도 있습니다. 이 경우 `userinfo.email` 및 `openid` 범위를 추가하고 앱을 내부용으로 표시해야
합니다.
<!-- -->
:::

#### Okta {#okta}

[OAuth 2.0](https://oauth.net/2/) 프로토콜을 통해 Okta 인증을 활성화할 수 있습니다.
<LocalizedLink href="/guides/integrations/sso#okta">이 지침</LocalizedLink>에 따라
Okta에서 [앱을
생성](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)해야
합니다.

Okta 애플리케이션 설정 과정에서 클라이언트 ID와 시크릿을 획득한 후 다음 환경 변수를 설정해야 합니다:

| 환경 변수                        | 설명                                                | 필수  | 기본 값 | 예   |
| ---------------------------- | ------------------------------------------------- | --- | ---- | --- |
| `TUIST_OKTA_1_CLIENT_ID`     | Okta 인증에 사용되는 클라이언트 ID입니다. 이 번호는 귀하의 조직 ID여야 합니다. | 예   |      |     |
| `TUIST_OKTA_1_CLIENT_SECRET` | Okta 인증에 사용되는 클라이언트 시크릿                           | 예   |      |     |

`1` 이 숫자는 귀하의 조직 ID로 대체해야 합니다. 일반적으로 1이지만, 데이터베이스에서 확인하시기 바랍니다.

### 저장 환경 구성 {#storage-environment-configuration}

Tuist는 API를 통해 업로드된 아티팩트를 저장할 저장 공간이 필요합니다. Tuist가 원활하게 작동하려면 지원되는 저장 솔루션 중 하나를
구성하는 것이 필수적입니다. ****

#### S3 호환 스토리지 {#s3compliant-storages}

아티팩트를 저장하려면 S3 호환 스토리지 제공업체를 사용할 수 있습니다. 스토리지 제공업체와의 통합을 인증하고 구성하려면 다음 환경 변수가
필요합니다:

| 환경 변수                                                   | 설명                                                                                                | 필수  | 기본 값       | 예                                                             |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | --- | ---------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` 또는 `AWS_ACCESS_KEY_ID`         | 스토리지 공급자에 대한 인증에 사용되는 액세스 키 ID                                                                    | 예   |            | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` 또는 `AWS_SECRET_ACCESS_KEY` | 스토리지 공급자에 대한 인증을 위한 비밀 액세스 키                                                                      | 예   |            | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` 또는 `AWS_REGION`                       | 버킷이 위치한 지역                                                                                        | 아니요 | `auto`     | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` 또는 `AWS_ENDPOINT`                   | 스토리지 공급자의 엔드포인트                                                                                   | 예   |            | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                  | 아티팩트가 저장될 버킷의 이름                                                                                  | 예   |            | `tuist-artifacts`                                             |
| `TUIST_S3_CA_CERT_PEM`                                  | S3 HTTPS 연결을 검증하기 위한 PEM 형식의 CA 인증서입니다. 자체 서명된 인증서나 내부 인증 기관(CA)을 사용하는 에어갭(air-gapped) 환경에 유용합니다. | 아니요 | 시스템 CA 번들  | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                              | 스토리지 공급자와의 연결을 설정하는 데 걸리는 시간 제한(밀리초 단위)                                                           | 아니요 | `3000`     | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                              | 스토리지 공급자로부터 데이터를 수신하는 데 걸리는 시간 제한(밀리초 단위)                                                         | 아니요 | `5000`     | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                                 | 스토리지 공급자에 대한 연결 풀의 타임아웃(밀리초 단위). 타임아웃을 설정하지 않으려면 `infinity` 를 사용하십시오.                             | 아니요 | `5000`     | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                           | 풀 내 연결의 최대 유휴 시간(밀리초 단위). 연결을 무기한 유지하려면 `infinity` 를 사용하십시오.                                      | 아니요 | `infinity` | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                    | 풀당 최대 연결 수                                                                                        | 아니요 | `500`      | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                   | 사용할 연결 풀의 수                                                                                       | 아니요 | 시스템 스케줄러 수 | `4`                                                           |
| `TUIST_S3_PROTOCOL`                                     | 스토리지 공급자에 연결할 때 사용할 프로토콜 (`http1` 또는 `http2`)                                                     | 아니요 | `http1`    | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                                 | URL을 구성할 때 버킷 이름을 서브도메인(가상 호스트)으로 사용할지 여부                                                         | 아니요 | `false`    | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
스토리지 제공업체가 AWS이고 웹 ID 토큰을 사용하여 인증하려는 경우, 환경 변수 `TUIST_S3_AUTHENTICATION_METHOD`
를 `aws_web_identity_token_from_env_vars` 로 설정하면, Tuist는 기존의 AWS 환경 변수를 사용하여 해당
방법을 적용합니다.
<!-- -->
:::

#### Google Cloud Storage {#google-cloud-storage}
Google Cloud Storage의 경우, [이
문서](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)을 따라
`AWS_ACCESS_KEY_ID` 및 `AWS_SECRET_ACCESS_KEY` 쌍을 가져오십시오. `AWS_ENDPOINT` 는
`https://storage.googleapis.com` 로 설정해야 합니다. 다른 환경 변수는 다른 S3 호환 스토리지와 동일합니다.

### 이메일 설정 {#email-configuration}

Tuist는 사용자 인증 및 트랜잭션 알림(예: 비밀번호 재설정, 계정 알림)을 위해 이메일 기능이 필요합니다. 현재 **에서는
Mailgun(** )만 이메일 제공자로 지원됩니다.

| 환경 변수                            | 설명                                                                            | 필수  | 기본 값                                   | 예                         |
| -------------------------------- | ----------------------------------------------------------------------------- | --- | -------------------------------------- | ------------------------- |
| `TUIST_MAILGUN_API_KEY`          | Mailgun 인증용 API 키                                                             | 예*  |                                        | `key-1234567890abcdef`    |
| `TUIST_MAILING_DOMAIN`           | 이메일이 발송될 도메인                                                                  | 예*  |                                        | `mg.tuist.io`             |
| `TUIST_MAILING_FROM_ADDRESS`     | "보낸 사람" 필드에 표시될 이메일 주소                                                        | 예*  |                                        | `noreply@tuist.io`        |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 사용자 답글용 선택적 회신 주소                                                             | 아니요 |                                        | `support@tuist.dev`       |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | 신규 사용자 등록 시 이메일 확인 단계를 생략합니다. 이 기능을 활성화하면 사용자는 자동으로 확인되며, 등록 후 바로 로그인할 수 있습니다 | 아니요 | `true` (이메일 미설정 시), `false` (이메일 설정 시) | `true`, `false`, `1`, `0` |

\* 이메일 설정 변수는 이메일을 보내고자 할 때만 필요합니다. 설정하지 않으면 이메일 확인 단계가 자동으로 건너뜁니다

::: info SMTP SUPPORT
<!-- -->
현재 일반 SMTP 지원은 제공되지 않습니다. 온프레미스 배포를 위해 SMTP 지원이 필요한 경우,
[contact@tuist.dev](mailto:contact@tuist.dev)으로 문의하여 요구 사항을 논의해 주십시오.
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
인터넷 접속이 불가능하거나 이메일 제공업체 설정이 되어 있지 않은 온프레미스 설치 환경에서는 기본적으로 이메일 확인 절차가 자동으로 건너뜁니다.
사용자는 등록 후 바로 로그인할 수 있습니다. 이메일이 설정되어 있지만 확인 절차를 건너뛰고 싶다면
`TUIST_SKIP_EMAIL_CONFIRMATION=true` 를 설정하십시오. 이메일이 설정된 경우 이메일 확인을 필수로 하려면
`TUIST_SKIP_EMAIL_CONFIRMATION=false` 를 설정하십시오.
<!-- -->
:::

### Git 플랫폼 구성 {#git-platform-configuration}

Tuist는 <LocalizedLink href="/guides/server/authentication">Git
플랫폼</LocalizedLink>과 연동되어 풀 리퀘스트에 자동으로 코멘트를 게시하는 등의 추가 기능을 제공합니다.

#### GitHub {#platform-github}

[GitHub 앱
생성](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)이
필요합니다. OAuth GitHub 앱을 생성한 경우가 아니라면, 인증용으로 생성한 앱을 재사용할 수 있습니다. `Permissions and
events` 의 `Repository permissions` 섹션에서, `Pull requests` 권한을 `Read and write` 로
추가로 설정해야 합니다.

`, TUIST_GITHUB_APP_CLIENT_ID`, `, TUIST_GITHUB_APP_CLIENT_SECRET` 외에도 다음 환경 변수가
필요합니다:

| 환경 변수                          | 설명                  | 필수  | 기본 값 | 예                                    |
| ------------------------------ | ------------------- | --- | ---- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub 애플리케이션의 개인 키 | 예   |      | `-----BEGIN RSA PRIVATE KEY-----...` |

## 로컬 테스트 {#testing-locally}

인프라에 배포하기 전에 로컬 머신에서 Tuist 서버를 테스트하는 데 필요한 모든 의존성을 포함하는 포괄적인 Docker Compose 구성을
제공합니다:

- PostgreSQL 15 및 TimescaleDB 2.16 확장 기능 (사용 중단됨)
- 분석을 위한 ClickHouse 25
- 조정 담당: ClickHouse Keeper
- S3 호환 스토리지를 위한 MinIO
- 배포 간 지속적 KV 스토리지를 위한 Redis (선택 사항)
- 데이터베이스 관리를 위한 pgweb

::: danger LICENSE REQUIRED
<!-- -->
Tuist 서버(로컬 개발 환경 포함)를 실행하려면 법적으로 유효한 `TUIST_LICENSE` 환경 변수가 필요합니다. 라이선스가 필요하시면
[contact@tuist.dev](mailto:contact@tuist.dev)으로 문의해 주십시오.
<!-- -->
:::

**빠른 시작:**

1. 구성 파일을 다운로드하세요:
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 환경 변수 설정:
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE and authentication credentials
   ```

3. 모든 서비스를 시작합니다:
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

4. http://localhost:8080에서 서버에 접속하세요

**서비스 엔드포인트:**
- Tuist 서버: http://localhost:8080
- MinIO 콘솔: http://localhost:9003 (인증 정보: `tuist` / `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus Metrics: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**일반적인 명령어:**

서비스 상태 확인:
```bash
docker compose ps
# or: podman compose ps
```

로그 보기:
```bash
docker compose logs -f tuist
```

서비스 중지:
```bash
docker compose down
```

모든 설정 초기화 (모든 데이터 삭제):
```bash
docker compose down -v
```

**구성 파일:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - 전체 Docker Compose
  구성
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse
  구성
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - ClickHouse Keeper 구성
- [.env.example](/server/self-host/.env.example) - 환경 변수 파일 예시

## 배포 {#deployment}

공식 Tuist Docker 이미지는 다음에서 확인할 수 있습니다:
```
ghcr.io/tuist/tuist
```

### Docker 이미지 가져오기 {#pulling-the-docker-image}

다음 명령어를 실행하면 이미지를 불러올 수 있습니다:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

또는 특정 버전을 불러오려면:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Docker 이미지 배포 {#deploying-the-docker-image}

Docker 이미지 배포 프로세스는 선택한 클라우드 공급자와 조직의 지속적 배포 방식에 따라 달라집니다.
[Kubernetes](https://kubernetes.io/)와 같은 대부분의 클라우드 솔루션 및 도구는 Docker 이미지를 기본 단위로
활용하므로, 이 섹션의 예시는 기존 환경과 잘 맞을 것입니다.

::: warning
<!-- -->
배포 파이프라인에서 서버가 정상적으로 가동 중인지 확인해야 하는 경우, `/ready` 로 `GET` HTTP 요청을 전송하고, 응답에서
`200` 상태 코드를 확인하면 됩니다.
<!-- -->
:::

#### 날다 {#fly}

[Fly](https://fly.io/)에 앱을 배포하려면 `fly.toml` 구성 파일이 필요합니다. 지속적 배포(CD) 파이프라인 내에서
이를 동적으로 생성하는 것을 고려해 보세요. 다음은 참고용 예시입니다:

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

그런 다음 `fly launch --local-only --no-deploy` 명령어를 실행하여 앱을 실행할 수 있습니다. 이후 배포 시에는
`fly launch --local-only` 명령어를 실행하는 대신, `fly deploy --local-only` 명령어를 실행해야 합니다.
Fly.io는 비공개 Docker 이미지를 가져올 수 없기 때문에 `--local-only` 플래그를 사용해야 합니다.


## 프로메테우스 메트릭스 {#prometheus-metrics}

Tuist는 자체 호스팅 인스턴스를 모니터링할 수 있도록 `/metrics` 에서 Prometheus 메트릭을 제공합니다. 이러한 메트릭에는
다음이 포함됩니다:

### Finch HTTP 클라이언트 메트릭 {#finch-metrics}

Tuist는 [Finch](https://github.com/sneako/finch)를 HTTP 클라이언트로 사용하며, HTTP 요청에 대한
상세한 메트릭을 제공합니다:

#### 지표 요청
- `tuist_prom_ex_finch_request_count_total` - Finch 요청 총 수 (카운터)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 요청 소요 시간 (히스토그램)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - 버킷: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 요청 예외의 총 개수 (카운터)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### 연결 풀 대기열 메트릭
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 연결 풀 대기열에서 대기한 시간 (히스토그램)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `pool`
  - 버킷: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 연결이 사용되기 전까지 유휴 상태로 머문 시간
  (히스토그램)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `pool`
  - 버킷: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 큐 예외 발생 총 횟수 (카운터)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### 연결 메트릭스
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 연결 설정에 소요된 시간 (히스토그램)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `error`
  - 버킷: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - 총 연결 시도 횟수 (카운터)
  - 라벨: `finch_name`, `scheme`, `host`, `port`

#### 메트릭 전송
- `tuist_prom_ex_finch_send_duration_milliseconds` - 요청 전송에 소요된 시간 (히스토그램)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - 버킷: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 전송 전 연결이 유휴 상태로 머문 시간
  (히스토그램)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - 버킷: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

모든 히스토그램 메트릭은 상세한 분석을 위해 `_bucket`, `_sum`, `_count` 변형을 제공합니다.

### 기타 지표

Finch 메트릭 외에도 Tuist는 다음 항목에 대한 메트릭을 제공합니다:
- BEAM 가상 머신 성능
- 사용자 정의 비즈니스 로직 지표(스토리지, 계정, 프로젝트 등)
- 데이터베이스 성능 (Tuist 호스팅 인프라 사용 시)

## 연산 {#operations}

Tuist는 `/ops/` 에서 인스턴스를 관리하는 데 사용할 수 있는 유틸리티 모음을 제공합니다.

::: warning Authorization
<!-- -->
`의 TUIST_OPS_USER_HANDLES` 환경 변수에 나열된 핸들을 가진 사용자만 `/ops/` 엔드포인트에 액세스할 수 있습니다.
<!-- -->
:::

- **오류 (`/ops/errors`):** 애플리케이션에서 발생한 예기치 않은 오류를 확인할 수 있습니다. 이는 디버깅 및 문제 원인을
  파악하는 데 유용하며, 문제가 발생할 경우 이 정보를 저희와 공유해 주실 것을 요청드릴 수 있습니다.
- **대시보드 (`/ops/dashboard`):** 애플리케이션의 성능 및 상태(예: 메모리 사용량, 실행 중인 프로세스, 요청 수)에 대한
  정보를 제공하는 대시보드를 확인할 수 있습니다. 이 대시보드는 사용 중인 하드웨어가 부하를 감당하기에 충분한지 파악하는 데 매우 유용합니다.
