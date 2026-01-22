---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# 자체 호스팅 설치 {#self-host-installation}

인프라에 대한 더 많은 통제가 필요한 조직을 위해 자체 호스팅 버전의 Tuist 서버를 제공합니다. 이 버전은 자체 인프라에서 Tuist를
호스팅할 수 있도록 하여 데이터의 보안과 프라이버시를 보장합니다.

::: warning LICENSE REQUIRED
<!-- -->
Tuist 자체 호스팅에는 법적으로 유효한 유료 라이선스가 필요합니다. Tuist 온프레미스 버전은 엔터프라이즈 플랜을 사용하는 조직에만
제공됩니다. 해당 버전에 관심이 있으시면 [contact@tuist.dev](mailto:contact@tuist.dev)으로 문의해 주십시오.
<!-- -->
:::

## 릴리스 주기 {#release-cadence}

우리는 메인 브랜치에 배포 가능한 변경 사항이 반영될 때마다 지속적으로 Tuist의 새 버전을 출시합니다. 예측 가능한 버전 관리와 호환성을
보장하기 위해 [세미틱 버전 관리](https://semver.org/)을 따릅니다.

주요 구성 요소는 Tuist 서버의 중대한 변경 사항을 표시하는 데 사용되며, 이는 온프레미스 사용자와의 협조가 필요합니다. 당사가 이를 사용할
것이라고 기대하지 마십시오. 필요한 경우, 전환을 원활하게 진행하기 위해 반드시 협력할 것임을 확신하십시오.

## 지속적 배포 {#continuous-deployment}

매일 최신 버전의 Tuist를 자동으로 배포하는 지속적 배포 파이프라인을 설정할 것을 강력히 권장합니다. 이를 통해 항상 최신 기능, 개선 사항
및 보안 업데이트를 이용할 수 있습니다.

다음은 매일 새 버전을 확인하고 배포하는 GitHub Actions 워크플로의 예시입니다:

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

## 실행 시 요구 사항 {#runtime-requirements}

이 섹션에서는 귀하의 인프라에 Tuist 서버를 호스팅하기 위한 요구 사항을 설명합니다.

### 호환성 매트릭스 {#compatibility-matrix}

Tuist 서버는 테스트를 거쳐 다음 최소 버전과 호환됩니다:

| 구성 요소       | 최소 버전  | 참고사항                         |
| ----------- | ------ | ---------------------------- |
| PostgreSQL  | 15     | TimescaleDB 확장 기능 사용 시       |
| TimescaleDB | 2.16.1 | 필수 PostgreSQL 확장 기능 (사용 중단됨) |
| ClickHouse  | 25     | 분석을 위해 필수                    |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB는 현재 Tuist 서버에 필수적인 PostgreSQL 확장 모듈로, 시계열 데이터 저장 및 쿼리 용도로 사용됩니다. 그러나
**TimescaleDB는 더 이상 권장되지 않으며** 모든 시계열 기능을 ClickHouse로 이전함에 따라 가까운 시일 내에 필수 종속성에서
제외될 예정입니다. 당분간은 PostgreSQL 인스턴스에 TimescaleDB가 설치 및 활성화되어 있는지 확인하십시오.
<!-- -->
:::

### Docker 가상화 이미지 실행 {#running-dockervirtualized-images}

우리는 [GitHub의 컨테이너
레지스트리](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)를
통해 [Docker](https://www.docker.com/) 이미지로 서버를 배포합니다.

이를 실행하려면 인프라가 Docker 이미지 실행을 지원해야 합니다. 대부분의 인프라 제공업체는 프로덕션 환경에서 소프트웨어 배포 및 실행을
위한 표준 컨테이너로 자리 잡았기 때문에 이를 지원합니다.

### Postgres 데이터베이스 {#postgres-database}

Docker 이미지를 실행하는 것 외에도, 관계형 및 시계열 데이터를 저장하기 위해 [TimescaleDB 확장
기능](https://www.timescale.com/)이 적용된 [Postgres
데이터베이스](https://www.postgresql.org/)이 필요합니다. 대부분의 인프라 제공업체는 자사 서비스에 Postgres
데이터베이스를 포함합니다(예: [AWS](https://aws.amazon.com/rds/postgresql/) 및 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)).

**TimescaleDB 확장 모듈 필수:** Tuist는 효율적인 시계열 데이터 저장 및 쿼리를 위해 TimescaleDB 확장 모듈이
필요합니다. 이 확장 모듈은 명령 이벤트, 분석 및 기타 시간 기반 기능에 사용됩니다. Tuist 실행 전에 PostgreSQL 인스턴스에
TimescaleDB가 설치 및 활성화되었는지 확인하십시오.

::: info MIGRATIONS
<!-- -->
Docker 이미지의 엔트리포인트는 서비스를 시작하기 전에 대기 중인 스키마 마이그레이션을 자동으로 실행합니다. TimescaleDB 확장
기능이 없어 마이그레이션이 실패할 경우, 먼저 데이터베이스에 해당 확장 기능을 설치해야 합니다.
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

파일(예: 프레임워크 및 라이브러리 바이너리)을 저장할 솔루션도 필요합니다. 현재 S3 호환 저장소를 모두 지원합니다.

::: tip OPTIMIZED CACHING
<!-- -->
바이너리 저장용 자체 버킷을 구축하고 캐시 지연 시간을 줄이는 것이 주 목적이라면, 서버 전체를 자체 호스팅할 필요는 없습니다. 캐시 노드만
자체 호스팅하고, 이를 호스팅된 Tuist 서버나 자체 호스팅 서버에 연결할 수 있습니다.

<LocalizedLink href="/guides/cache/self-host">캐시 자체 호스팅 가이드</LocalizedLink>를
참조하십시오.
<!-- -->
:::

## 환경 설정 {#configuration}

서비스 구성은 런타임 시 환경 변수를 통해 이루어집니다. 이러한 변수의 민감한 특성을 고려하여, 암호화 후 안전한 비밀번호 관리 솔루션에 저장할
것을 권장합니다. Tuist는 이러한 변수를 극도로 신중하게 처리하며, 로그에 절대 노출되지 않도록 보장합니다.

::: info LAUNCH CHECKS
<!-- -->
필수 변수들은 시작 시점에 검증됩니다. 누락된 변수가 있을 경우 실행이 실패하며, 오류 메시지에 누락된 변수들이 상세히 표시됩니다.
<!-- -->
:::

### 라이선스 구성 {#license-configuration}

온프레미스 사용자의 경우, 환경 변수로 노출해야 하는 라이선스 키를 받게 됩니다. 이 키는 라이선스를 검증하고 서비스가 계약 조건 내에서
실행되도록 보장하는 데 사용됩니다.

| 환경 변수                              | 설명                                                                                                                               | 필수  | 기본 값 | 예                                         |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | --- | ---- | ----------------------------------------- |
| `TUIST_LICENSE`                    | 서비스 수준 계약서 서명 후 제공되는 라이선스                                                                                                        | 예*  |      | `******`                                  |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **`TUIST_LICENSE`의 예외적 대안**. 서버가 외부 서비스와 통신할 수 없는 에어갭 환경에서 오프라인 라이선스 검증을 위한 Base64 인코딩 공개 인증서. `TUIST_LICENSE` 사용 불가 시에만 사용하십시오. | 예*  |      | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* 다음 중 하나만 제공해야 합니다: `TUIST_LICENSE` ` TUIST_LICENSE_CERTIFICATE_BASE64` 표준
배포에는 `TUIST_LICENSE` 를 사용하십시오.

::: warning EXPIRATION DATE
<!-- -->
라이선스에는 만료일이 있습니다. 라이선스 만료일이 30일 미만인 경우, 서버와 상호작용하는 Tuist 명령어를 사용할 때 사용자에게 경고가
표시됩니다. 라이선스 갱신을 원하시면 [contact@tuist.dev](mailto:contact@tuist.dev)으로 문의해 주십시오.
<!-- -->
:::

### 기본 환경 구성 {#base-environment-configuration}

| 환경 변수                                 | 설명                                                                                             | 필수  | 기본 값                               | 예                                                                   |                                                                                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------------------------- | --- | ---------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                       | 인터넷에서 인스턴스에 접근하기 위한 기본 URL                                                                     | 예   |                                    | https://tuist.dev                                                   |                                                                                                                                    |
| `TUIST_SECRET_KEY_BASE`               | 정보(예: 쿠키 내 세션)를 암호화하는 데 사용하는 키                                                                 | 예   |                                    |                                                                     | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD`           | 해시된 비밀번호 생성을 위한 Pepper                                                                         | 아니요 | `$TUIST_SECRET_KEY_BASE`           |                                                                     |                                                                                                                                    |
| `TUIST_SECRET_KEY_TOKENS`             | 랜덤 토큰 생성용 비밀 키                                                                                 | 아니요 | `$TUIST_SECRET_KEY_BASE`           |                                                                     |                                                                                                                                    |
| `TUIST_SECRET_KEY_ENCRYPTION`         | 민감한 데이터의 AES-GCM 암호화를 위한 32바이트 키                                                               | 아니요 | `$TUIST_SECRET_KEY_BASE`           |                                                                     |                                                                                                                                    |
| `TUIST_USE_IPV6`                      | `1` 이 설정은 앱이 IPv6 주소를 사용하도록 구성합니다.                                                             | 아니요 | `0`                                | `1`                                                                 |                                                                                                                                    |
| `TUIST_LOG_LEVEL`                     | 앱에 사용할 로그 수준                                                                                   | 아니요 | `info`                             | [로그 수준](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `TUIST_GITHUB_APP_NAME`               | GitHub 앱 이름의 URL 버전                                                                            | 아니요 |                                    | `my-app`                                                            |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | GitHub 앱에서 자동 PR 댓글 작성과 같은 추가 기능을 활성화하는 데 사용되는 base64로 인코딩된 개인 키                               | 아니요 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                     |                                                                                                                                    |
| `TUIST_GITHUB_APP_PRIVATE_KEY`        | 자동 PR 댓글 작성 등 추가 기능을 활성화하는 GitHub 앱용 개인 키. **특수 문자 관련 문제를 방지하려면 base64 인코딩 버전을 사용하는 것이 좋습니다.** | 아니요 | `-----BEGIN RSA...`                |                                                                     |                                                                                                                                    |
| `TUIST_OPS_USER_HANDLES`              | 작업 URL에 접근 권한이 있는 사용자 핸들들의 쉼표로 구분된 목록                                                          | 아니요 |                                    | `user1,user2`                                                       |                                                                                                                                    |
| `TUIST_WEB`                           | 웹 서버 엔드포인트 활성화                                                                                 | 아니요 | `1`                                | `1` 또는 `0`                                                          |                                                                                                                                    |

### 데이터베이스 구성 {#database-configuration}

다음 환경 변수는 데이터베이스 연결을 구성하는 데 사용됩니다:

| 환경 변수                                | 설명                                                                                                                                               | 필수  | 기본 값      | 예                                                                      |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | Postgres 데이터베이스에 접근하기 위한 URL입니다. URL에는 인증 정보가 포함되어야 합니다.                                                                                         | 예   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL`               | ClickHouse 데이터베이스에 접근하기 위한 URL입니다. URL에는 인증 정보가 포함되어야 합니다.                                                                                       | 아니요 |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `TUIST_USE_SSL_FOR_DATABASE`         | true일 경우 데이터베이스 연결에 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security)을 사용합니다                                                         | 아니요 | `1`       | `1`                                                                    |
| `TUIST_DATABASE_POOL_SIZE`           | 연결 풀에서 유지할 연결 수                                                                                                                                  | 아니요 | `10`      | `10`                                                                   |
| `TUIST_DATABASE_QUEUE_TARGET`        | 풀에서 체크아웃된 모든 연결이 대기열 간격보다 오래 걸렸는지 확인하는 간격(밀리초 단위) [(자세한 정보)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config)       | 아니요 | `300`     | `300`                                                                  |
| `TUIST_DATABASE_QUEUE_INTERVAL`      | 풀이 새 연결을 거부하기 시작할지 여부를 결정하는 데 사용하는 대기열 내 임계값 시간(밀리초 단위) [(자세한 정보)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 아니요 | `1000`    | `1000`                                                                 |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | ClickHouse 버퍼 플러시 간격(밀리초)                                                                                                                        | 아니요 | `5000`    | `5000`                                                                 |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE`   | 강제 플러시 전 최대 ClickHouse 버퍼 크기(바이트)                                                                                                                | 아니요 | `1000000` | `1000000`                                                              |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE`  | 실행할 ClickHouse 버퍼 프로세스 수                                                                                                                         | 아니요 | `5`       | `5`                                                                    |

### 인증 환경 구성 {#authentication-environment-configuration}

우리는 [아이덴티티 프로바이더(IdP)](https://en.wikipedia.org/wiki/Identity_provider)을 통한 인증을
지원합니다. 이를 활용하려면 선택한 프로바이더에 필요한 모든 환경 변수가 서버 환경에 존재하는지 확인하십시오. **누락된 변수** 는
Tuist가 해당 프로바이더를 우회하도록 합니다.

#### GitHub {#github}

[GitHub
앱](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)을
사용한 인증을 권장하지만 [OAuth
앱](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)도
사용할 수 있습니다. GitHub에서 지정한 모든 필수 환경 변수를 서버 환경에 포함해야 합니다. 변수가 누락되면 Tuist가 GitHub
인증을 인식하지 못합니다. GitHub 앱을 올바르게 설정하려면:
- GitHub 앱의 일반 설정에서:
    - `에서 클라이언트 ID(` )를 복사하여 `TUIST_GITHUB_APP_CLIENT_ID로 설정하십시오.`
    - 새 `클라이언트 시크릿 생성 및 복사` 이를 `TUIST_GITHUB_APP_CLIENT_SECRET로 설정하십시오.`
    - `콜백 URL 설정` ` http://YOUR_APP_URL/users/auth/github/callback`.
      `YOUR_APP_URL` 서버의 IP 주소로도 설정 가능합니다.
- 다음 권한이 필요합니다:
  - 저장소:
    - 풀 리퀘스트: 읽고 쓰기
  - 계정:
    - 이메일 주소: 읽기 전용

`의 Permissions and events(권한 및 이벤트)` 섹션에서 `Account permissions(계정 권한)` 항목의
`Email addresses(이메일 주소)` 권한을 `Read-only(읽기 전용)` 로 설정하십시오.

그런 다음 Tuist 서버가 실행되는 환경에서 다음 환경 변수를 노출해야 합니다:

| 환경 변수                            | 설명                      | 필수  | 기본 값 | 예                                          |
| -------------------------------- | ----------------------- | --- | ---- | ------------------------------------------ |
| `TUIST_GITHUB_APP_CLIENT_ID`     | GitHub 애플리케이션의 클라이언트 ID | 예   |      | `Iv1.a629723000043722`                     |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | 애플리케이션의 클라이언트 시크릿       | 예   |      | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

Google 인증은 [OAuth 2](https://developers.google.com/identity/protocols/oauth2)을
사용하여 설정할 수 있습니다. 이를 위해 OAuth 클라이언트 ID 유형의 새 자격 증명을 생성해야 합니다. 자격 증명 생성 시 애플리케이션
유형으로 "웹 애플리케이션"을 선택하고, 이름을 `Tuist` 로 지정하며, 리디렉션 URI를
`{base_url}/users/auth/google/callback` 로 설정합니다. 여기서 `base_url` 는 호스팅 서비스가 실행 중인
URL입니다. 앱을 생성한 후 클라이언트 ID와 비밀번호를 복사하여 각각 환경 변수로 설정하세요. `GOOGLE_CLIENT_ID` `
GOOGLE_CLIENT_SECRET`

::: info CONSENT SCREEN SCOPES
<!-- -->
동의 화면을 생성해야 할 수 있습니다. 생성 시 다음 스코프를 추가하고 앱을 내부용으로 표시하세요: `userinfo.email` `
openid`
<!-- -->
:::

#### Okta {#okta}

[OAuth 2.0](https://oauth.net/2/) 프로토콜을 통해 Okta 인증을 활성화할 수 있습니다.
<LocalizedLink href="/guides/integrations/sso#okta">이 지침</LocalizedLink>에 따라
Okta에서 [앱
생성](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)해야
합니다.

Okta 애플리케이션 설정 과정에서 클라이언트 ID와 시크릿을 획득한 후 다음 환경 변수를 설정해야 합니다:

| 환경 변수                        | 설명                                           | 필수  | 기본 값 | 예   |
| ---------------------------- | -------------------------------------------- | --- | ---- | --- |
| `TUIST_OKTA_1_CLIENT_ID`     | Okta 인증을 위한 클라이언트 ID. 이 번호는 귀사의 조직 ID여야 합니다. | 예   |      |     |
| `TUIST_OKTA_1_CLIENT_SECRET` | Okta 인증을 위한 클라이언트 시크릿                        | 예   |      |     |

`1` 번호는 귀하의 조직 ID로 대체해야 합니다. 일반적으로 1이지만 데이터베이스에서 확인하십시오.

### 저장 환경 구성 {#storage-environment-configuration}

Tuist는 API를 통해 업로드된 아티팩트를 저장할 저장 공간이 필요합니다. Tuist가 효과적으로 작동하려면 지원되는 저장 솔루션 중 하나를
구성하는 것이 필수적입니다. ****

#### S3 호환 스토리지 {#s3compliant-storages}

아티팩트 저장을 위해 S3 호환 스토리지 제공업체를 사용할 수 있습니다. 스토리지 제공업체와의 통합 인증 및 구성을 위해 다음 환경 변수가
필요합니다:

| 환경 변수                                                   | 설명                                                                                  | 필수  | 기본 값       | 예                                                             |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------- | --- | ---------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` 또는 `AWS_ACCESS_KEY_ID`         | 스토리지 공급자에 대한 인증을 위한 액세스 키 ID                                                        | 예   |            | `AKIAIOSFOD`                                                  |
| `TUIST_S3_SECRET_ACCESS_KEY` 또는 `AWS_SECRET_ACCESS_KEY` | 스토리지 공급자에 대한 인증을 위한 비밀 액세스 키                                                        | 예   |            | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` 또는 `AWS_REGION`                       | 버킷이 위치한 지역                                                                          | 아니요 | `auto`     | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` 또는 `AWS_ENDPOINT`                   | 스토리지 공급자의 엔드포인트                                                                     | 예   |            | `https://s3.us-west-2.amazonaws.com`                          |
| `TUIST_S3_BUCKET_NAME`                                  | 아티팩트가 저장될 버킷의 이름                                                                    | 예   |            | `tuist-artifacts`                                             |
| `TUIST_S3_CA_CERT_PEM`                                  | S3 HTTPS 연결을 검증하기 위한 PEM 인코딩된 CA 인증서. 자체 서명 인증서나 내부 인증 기관(CA)을 사용하는 에어갭 환경에서 유용합니다. | 아니요 | 시스템 CA 번들  | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT`                              | 스토리지 공급자에 대한 연결 설정 시간 제한(밀리초 단위)                                                    | 아니요 | `3000`     | `3000`                                                        |
| `TUIST_S3_RECEIVE_TIMEOUT`                              | 스토리지 공급자로부터 데이터를 수신하는 데 허용되는 시간 초과(밀리초 단위)                                          | 아니요 | `5000`     | `5000`                                                        |
| `TUIST_S3_POOL_TIMEOUT`                                 | 스토리지 공급자에 대한 연결 풀의 시간 제한(밀리초 단위). 시간 제한을 없애려면 `infinity` 를 사용하십시오.                  | 아니요 | `5000`     | `5000`                                                        |
| `TUIST_S3_POOL_MAX_IDLE_TIME`                           | 풀 내 연결의 최대 유휴 시간(밀리초 단위). 연결을 무기한 유지하려면 ` `` 또는 `infinity`(` )를 사용하십시오.             | 아니요 | `infinity` | `60000`                                                       |
| `TUIST_S3_POOL_SIZE`                                    | 풀당 최대 연결 수                                                                          | 아니요 | `500`      | `500`                                                         |
| `TUIST_S3_POOL_COUNT`                                   | 사용할 연결 풀의 수                                                                         | 아니요 | 시스템 스케줄러 수 | `4`                                                           |
| `TUIST_S3_PROTOCOL`                                     | 스토리지 공급자에 연결할 때 사용할 프로토콜 (`http1` 또는 `http2`)                                       | 아니요 | `http1`    | `http1`                                                       |
| `TUIST_S3_VIRTUAL_HOST`                                 | URL을 버킷 이름을 서브도메인(가상 호스트)으로 구성해야 하는지 여부                                             | 아니요 | `false`    | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
저장소 제공자가 AWS이고 웹 ID 토큰을 사용해 인증하려면 환경 변수 `TUIST_S3_AUTHENTICATION_METHOD` 를
`aws_web_identity_token_from_env_vars` 로 설정하면, Tuist는 표준 AWS 환경 변수를 사용해 해당 방법을
적용합니다.
<!-- -->
:::

#### Google Cloud Storage {#google-cloud-storage}
`Google Cloud Storage의 경우, [해당
문서](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)을 따라
AWS_ACCESS_KEY_ID` 및 `AWS_SECRET_ACCESS_KEY` 쌍을 획득하십시오. `AWS_ENDPOINT` 는
`https://storage.googleapis.com` 로 설정해야 합니다. 기타 환경 변수는 다른 S3 호환 스토리지와 동일합니다.

### 이메일 설정 {#email-configuration}

Tuist는 사용자 인증 및 거래 알림(예: 비밀번호 재설정, 계정 알림)을 위해 이메일 기능이 필요합니다. 현재 **에서는 이메일 제공자로
Mailgun(** )만 지원됩니다.

| 환경 변수                            | 설명                                                                   | 필수  | 기본 값                                            | 예                         |
| -------------------------------- | -------------------------------------------------------------------- | --- | ----------------------------------------------- | ------------------------- |
| `TUIST_MAILGUN_API_KEY`          | Mailgun 인증용 API 키                                                    | 예*  |                                                 | `key-1234567890abcdef`    |
| `TUIST_MAILING_DOMAIN`           | 이메일이 발송될 도메인                                                         | 예*  |                                                 | `mg.tuist.io`             |
| `TUIST_MAILING_FROM_ADDRESS`     | "보낸 사람" 필드에 표시될 이메일 주소                                               | 예*  |                                                 | `noreply@tuist.io`        |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | 사용자 회신을 위한 선택적 회신 주소                                                 | 아니요 |                                                 | `support@tuist.dev`       |
| `TUIST_SKIP_EMAIL_CONFIRMATION`  | 신규 사용자 등록 시 이메일 확인을 생략합니다. 활성화 시 사용자는 자동으로 확인되며 등록 후 즉시 로그인할 수 있습니다. | 아니요 | `이메일 설정되지 않은 경우 true`, 이메일 설정된 경우 false `false` | `true`, `false`, `1`, `0` |

\* 이메일 발송을 원할 경우에만 이메일 설정 변수가 필요합니다. 설정하지 않으면 이메일 확인이 자동으로 생략됩니다.

::: info SMTP SUPPORT
<!-- -->
일반적인 SMTP 지원은 현재 제공되지 않습니다. 온프레미스 배포를 위한 SMTP 지원이 필요한 경우, 요구 사항을 논의하기 위해
[contact@tuist.dev](mailto:contact@tuist.dev)으로 문의하십시오.
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
인터넷 접속이 불가능하거나 이메일 제공자 설정이 없는 온프레미스 설치 환경에서는 기본적으로 이메일 확인이 자동으로 생략됩니다. 사용자는 등록 후
즉시 로그인할 수 있습니다. 이메일이 설정되어 있지만 확인을 생략하려면 `TUIST_SKIP_EMAIL_CONFIRMATION=true` 를
설정하세요. 이메일이 설정된 경우 이메일 확인을 필수로 하려면 `TUIST_SKIP_EMAIL_CONFIRMATION=false` 를
설정하세요.
<!-- -->
:::

### Git 플랫폼 구성 {#git-platform-configuration}

Tuist는 <LocalizedLink href="/guides/server/authentication">Git 플랫폼과
통합</LocalizedLink>하여 풀 리퀘스트에 자동으로 코멘트를 게시하는 등의 추가 기능을 제공합니다.

#### GitHub {#platform-github}

GitHub 앱을 [생성해야
합니다](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps).
OAuth GitHub 앱을 생성하지 않은 경우, 인증용으로 생성한 앱을 재사용할 수 있습니다. `권한 및 이벤트` 의 `저장소 권한`
섹션에서, `풀 리퀘스트` 권한을 `읽기 및 쓰기` 로 추가 설정해야 합니다.

`TUIST_GITHUB_APP_CLIENT_ID` 및 `TUIST_GITHUB_APP_CLIENT_SECRET` 에 더해, 다음 환경 변수가
필요합니다:

| 환경 변수                          | 설명                  | 필수  | 기본 값 | 예                                    |
| ------------------------------ | ------------------- | --- | ---- | ------------------------------------ |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | GitHub 애플리케이션의 개인 키 | 예   |      | `-----BEGIN RSA PRIVATE KEY-----...` |

## 로컬 테스트 {#testing-locally}

인프라에 배포하기 전에 로컬 머신에서 Tuist 서버를 테스트하는 데 필요한 모든 종속성을 포함하는 포괄적인 Docker Compose 구성을
제공합니다:

- PostgreSQL 15 with TimescaleDB 2.16 확장 모듈 (사용 중단됨)
- 분석을 위한 ClickHouse 25
- ClickHouse Keeper를 통한 조정
- MinIO for S3 호환 스토리지
- 배포 간 지속적 KV 저장소용 Redis (선택 사항)
- pgweb 데이터베이스 관리 도구

::: danger LICENSE REQUIRED
<!-- -->
Tuist 서버(로컬 개발 인스턴스 포함) 실행을 위해 법적으로 유효한 환경 변수 ` `` 또는 `` `가 필요합니다. 라이선스가 필요하시면
[contact@tuist.dev](mailto:contact@tuist.dev)로 문의해 주십시오.
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

3. 모든 서비스를 시작하십시오:
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

4. 서버에 접속하려면 http://localhost:8080

**서비스 엔드포인트:**
- Tuist 서버: http://localhost:8080
- MinIO 콘솔: http://localhost:9003 (인증 정보: `tuist` / `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- 프로메테우스 메트릭스: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**일반 명령어:**

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

모든 것을 초기화합니다(모든 데이터 삭제):
```bash
docker compose down -v
```

**구성 파일:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - Docker Compose 구성
  완료
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse
  구성
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml)
  - ClickHouse Keeper 구성
- [.env.example](/server/self-host/.env.example) - 예시 환경 변수 파일

## 배포 {#deployment}

공식 Tuist Docker 이미지는 다음에서 이용 가능합니다:
```
ghcr.io/tuist/tuist
```

### Docker 이미지 끌어오기 {#pulling-the-docker-image}

다음 명령어를 실행하여 이미지를 가져올 수 있습니다:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

또는 특정 버전을 가져오세요:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Docker 이미지 배포 {#deploying-the-docker-image}

Docker 이미지 배포 프로세스는 선택한 클라우드 공급자와 조직의 지속적 배포 방식에 따라 달라집니다.
[Kubernetes](https://kubernetes.io/)과 같은 대부분의 클라우드 솔루션 및 도구는 Docker 이미지를 기본 단위로
활용하므로, 본 섹션의 예시는 기존 환경과 잘 부합할 것입니다.

::: warning
<!-- -->
배포 파이프라인에서 서버 가동 상태를 검증해야 하는 경우, `GET` HTTP 요청을 `/ready` 로 전송하고 응답에서 `200` 상태
코드를 확인하십시오.
<!-- -->
:::

#### Fly {#fly}

[Fly](https://fly.io/)에 앱을 배포하려면 `fly.toml` 구성 파일이 필요합니다. 지속적 배포(CD) 파이프라인 내에서
동적으로 생성하는 것을 고려하십시오. 아래는 참고용 예시입니다:

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

그런 다음 `fly launch --local-only --no-deploy` 를 실행하여 앱을 시작할 수 있습니다. 이후 배포 시에는 `fly
launch --local-only` 를 실행하는 대신 `fly deploy --local-only` 를 실행해야 합니다. Fly.io는 비공개
Docker 이미지를 가져오는 것을 허용하지 않으므로 `--local-only` 플래그를 사용해야 합니다.


## 프로메테우스 메트릭스 {#prometheus-metrics}

Tuist는 자체 호스팅 인스턴스 모니터링을 지원하기 위해 `/metrics 및` 에서 Prometheus 메트릭을 노출합니다. 해당 메트릭에는
다음이 포함됩니다:

### 핀치 HTTP 클라이언트 메트릭스 {#finch-metrics}

Tuist는 HTTP 클라이언트로 [Finch](https://github.com/sneako/finch)을 사용하며 HTTP 요청에 대한
상세한 메트릭을 노출합니다:

#### 메트릭 요청
- `tuist_prom_ex_finch_request_count_total` - Finch 요청 총 횟수 (카운터)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 요청 지속 시간 (히스토그램)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - 버킷: 10ms, 50ms, 100ms, 250ms, 500ms, 1초, 2.5초, 5초, 10초
- `tuist_prom_ex_finch_request_exception_count_total` - Finch 요청 예외 총 횟수 (카운터)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### 연결 풀 대기열 메트릭스
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 연결 풀 대기열에서 소요된 대기 시간
  (히스토그램)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `pool`
  - 버킷: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 사용되기 전 연결이 유휴 상태로 보낸 시간
  (히스토그램)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `pool`
  - 버킷: 10ms, 50ms, 100ms, 250ms, 500ms, 1초, 5초, 10초
- `tuist_prom_ex_finch_queue_exception_count_total` - Finch 큐 예외 총 발생 횟수 (카운터)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### 연결 지표
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 연결 설정 소요 시간 (히스토그램)
  - 라벨: `finch_name`, `scheme`, `host`, `port`, `error`
  - 버킷: 10ms, 50ms, 100ms, 250ms, 500ms, 1초, 2.5초, 5초
- `tuist_prom_ex_finch_connect_count_total` - 총 연결 시도 횟수 (카운터)
  - 라벨: `finch_name`, `scheme`, `host`, `port`

#### 메트릭스 전송
- `tuist_prom_ex_finch_send_duration_milliseconds` - 요청 전송 소요 시간 (히스토그램)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - 버킷: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 전송 전 연결이 유휴 상태로 보낸 시간
  (히스토그램)
  - 라벨: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - 버킷: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

모든 히스토그램 메트릭은 상세 분석을 위해 `_bucket`, `_sum`, `_count` 변형을 제공합니다.

### 기타 지표

Finch 메트릭 외에도 Tuist는 다음에 대한 메트릭을 노출합니다:
- BEAM 가상 머신 성능
- 사용자 정의 비즈니스 로직 메트릭(스토리지, 계정, 프로젝트 등)
- 데이터베이스 성능 (Tuist 호스팅 인프라 사용 시)

## 연산 {#operations}

Tuist는 `/ops/ 및` 아래에서 인스턴스 관리를 위한 유틸리티 세트를 제공합니다.

::: warning Authorization
<!-- -->
`` 환경 변수(TUIST_OPS_USER_HANDLES)에 명시된 핸들을 가진 사용자만 /ops/ 및 엔드포인트에 접근할 수 있습니다. ``
<!-- -->
:::

- **오류 (`/ops/errors`):** 애플리케이션에서 발생한 예기치 않은 오류를 확인할 수 있습니다. 디버깅 및 문제 원인 파악에
  유용하며, 문제가 발생할 경우 해당 정보를 공유해 달라고 요청할 수 있습니다.
- **대시보드 (`/ops/dashboard`):** 애플리케이션의 성능 및 상태(예: 메모리 사용량, 실행 중인 프로세스, 요청 수)에 대한
  통찰력을 제공하는 대시보드를 확인할 수 있습니다. 이 대시보드는 사용 중인 하드웨어가 부하를 처리하기에 충분한지 파악하는 데 매우 유용할 수
  있습니다.
