---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# 셀프 호스트 설치 {#self-host-installation}

인프라에 대한 더 많은 제어가 필요한 조직을 위해 자체 호스팅 버전의 Tuist 서버를 제공합니다. 이 버전을 사용하면 자체 인프라에서
Tuist를 호스팅하여 데이터를 안전하게 비공개로 유지할 수 있습니다.

::: warning LICENSE REQUIRED
<!-- -->
자체 호스팅 Tuist에는 법적으로 유효한 유료 라이선스가 필요합니다. 온프레미스 버전의 Tuist는 Enterprise 요금제를 사용하는
조직만 사용할 수 있습니다. 이 버전에 관심이 있으시면 [contact@tuist.dev](mailto:contact@tuist.dev)로
문의하시기 바랍니다.
<!-- -->
:::

## 릴리스 케이던스 {#release-cadence}

새로운 릴리즈 가능한 변경 사항이 메인에 적용되면 지속적으로 새 버전을 출시합니다. 예측 가능한 버전 관리와 호환성을 보장하기 위해 [시맨틱
버전 관리](https://semver.org/)를 따릅니다.

주요 구성 요소는 온프레미스 사용자와의 조정이 필요한 Tuist 서버의 중대한 변경 사항을 알리는 데 사용됩니다. 당사가 이 기능을 사용할
필요는 없으며, 필요한 경우 당사는 원활한 전환을 위해 여러분과 협력할 것이니 안심하세요.

## 지속적인 배포 {#continuous-deployment}

매일 최신 버전의 Tuist를 자동으로 배포하는 지속적인 배포 파이프라인을 설정하는 것을 적극 권장합니다. 이렇게 하면 항상 최신 기능, 개선
사항 및 보안 업데이트에 액세스할 수 있습니다.

다음은 매일 새 버전을 확인하고 배포하는 GitHub 작업 워크플로 예시입니다:

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

## 런타임 요구 사항 {#runtime-requirements}

이 섹션에서는 인프라에서 Tuist 서버를 호스팅하기 위한 요구 사항을 간략하게 설명합니다.

### 호환성 매트릭스 {#compatibility-matrix}

Tuist 서버는 테스트를 거쳤으며 다음 최소 버전과 호환됩니다:

| 구성 요소      | 최소 버전  | 참고                             |
| ---------- | ------ | ------------------------------ |
| PostgreSQL | 15     | 타임스케일DB 확장 사용                  |
| 타임스케일DB    | 2.16.1 | 필수 PostgreSQL 확장(더 이상 사용되지 않음) |
| ClickHouse | 25     | 분석에 필요                         |

::: warning TIMESCALEDB DEPRECATION
<!-- -->
타임스케일DB는 현재 시계열 데이터 저장 및 쿼리에 사용되는 Tuist 서버의 필수 PostgreSQL 확장 프로그램입니다. 그러나
**TimescaleDB는 더 이상 사용되지 않으며** 가까운 시일 내에 모든 시계열 기능을 ClickHouse로 마이그레이션함에 따라 필수
종속성에서 삭제될 예정입니다. 현재로서는 PostgreSQL 인스턴스에 타임스케일DB가 설치되어 있고 활성화되어 있는지 확인하세요.
<!-- -->
:::

### Docker 가상화 이미지 실행 {#running-dockervirtualized-images}

GitHub의 컨테이너
레지스트리](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)를
통해 [Docker](https://www.docker.com/) 이미지로 서버를 배포합니다.

이를 실행하려면 인프라가 Docker 이미지 실행을 지원해야 합니다. 프로덕션 환경에서 소프트웨어를 배포하고 실행하기 위한 표준 컨테이너가
되었기 때문에 대부분의 인프라 제공업체가 이를 지원합니다.

### Postgres 데이터베이스 {#postgres-database}

Docker 이미지를 실행하는 것 외에도 관계형 및 시계열 데이터를 저장하려면 [TimescaleDB
확장](https://www.timescale.com/)이 있는 [Postgres
데이터베이스](https://www.postgresql.org/)가 필요합니다. 대부분의 인프라 제공업체는
[AWS](https://aws.amazon.com/rds/postgresql/) 및 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)와 같은 서비스 제공에 Postgres 데이터베이스를
포함합니다(예: [AWS](https://aws.amazon.com/rds/postgresql/) 및 [Google
Cloud](https://cloud.google.com/sql/docs/postgres)).

**타임스케일DB 확장이 필요합니다:** 효율적인 시계열 데이터 저장 및 쿼리를 위해 튜이스트에는 타임스케일DB 확장이 필요합니다. 이 확장은
명령 이벤트, 분석 및 기타 시간 기반 기능에 사용됩니다. 튜이스트를 실행하기 전에 PostgreSQL 인스턴스에 타임스케일DB가 설치되어 있고
활성화되어 있는지 확인하세요.

::: info MIGRATIONS
<!-- -->
Docker 이미지의 엔트리포인트는 서비스를 시작하기 전에 보류 중인 모든 스키마 마이그레이션을 자동으로 실행합니다. 타임스케일DB 확장이
누락되어 마이그레이션이 실패하는 경우, 먼저 데이터베이스에 해당 확장을 설치해야 합니다.
<!-- -->
:::

### ClickHouse 데이터베이스 {#clickhouse-database}

Tuist는 대량의 분석 데이터를 저장하고 쿼리하기 위해 [ClickHouse](https://clickhouse.com/)를 사용합니다.
ClickHouse는 인사이트 구축과 같은 기능에 **** 필요하며, 향후 타임스케일DB를 단계적으로 폐지함에 따라 기본 시계열 데이터베이스가
될 것입니다. ClickHouse를 자체 호스팅할지 아니면 호스팅된 서비스를 사용할지 선택할 수 있습니다.

::: info MIGRATIONS
<!-- -->
Docker 이미지의 엔트리포인트는 서비스를 시작하기 전에 보류 중인 모든 ClickHouse 스키마 마이그레이션을 자동으로 실행합니다.
<!-- -->
:::

### 스토리지 {#storage}

또한 파일(예: 프레임워크 및 라이브러리 바이너리)을 저장할 솔루션이 필요합니다. 현재는 S3와 호환되는 모든 스토리지를 지원합니다.

## 구성 {#configuration}

서비스 구성은 런타임에 환경 변수를 통해 이루어집니다. 이러한 변수의 민감한 특성을 고려할 때 안전한 비밀번호 관리 솔루션에 암호화하여 저장하는
것이 좋습니다. Tuist는 이러한 변수를 매우 신중하게 처리하여 로그에 절대 표시되지 않도록 하므로 안심하셔도 됩니다.

::: info LAUNCH CHECKS
<!-- -->
시작 시 필요한 변수가 확인됩니다. 누락된 변수가 있으면 실행이 실패하고 오류 메시지에 누락된 변수가 자세히 표시됩니다.
<!-- -->
:::

### 라이선스 구성 {#license-configuration}

온프레미스 사용자는 환경 변수로 노출해야 하는 라이선스 키를 받게 됩니다. 이 키는 라이선스의 유효성을 검사하고 서비스가 계약 조건 내에서
실행되고 있는지 확인하는 데 사용됩니다.

| 환경 변수                 | 설명                                                                                                                                     | 필수  | 기본값 | 예                                         |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | --- | --- | ----------------------------------------- |
| `TUIST_LICENSE`       | 서비스 수준 계약 체결 후 제공되는 라이선스                                                                                                               | 예*  |     | `******`                                  |
| `튜이스트_라이센스_인증서_베이스64` | **튜이스트_라이센스`의 탁월한 대안**. 서버가 외부 서비스와 연결할 수 없는 에어 갭 환경에서 오프라인 라이선스 유효성 검사를 위한 Base64 인코딩된 공인 인증서입니다. ` TUIST_LICENSE` 를 사용할 수 없는 경우에만 사용 | 예*  |     | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* `TUIST_LICENSE` 또는 `TUIST_LICENSE_CERTIFICATE_BASE64` 중 하나만 제공해야 하며, 둘 다 제공하면
안 됩니다. 표준 배포의 경우 `TUIST_LICENSE` 을 사용합니다.

::: warning EXPIRATION DATE
<!-- -->
라이선스에는 만료일이 있습니다. 라이선스가 30일 이내에 만료되면 서버와 상호 작용하는 Tuist 명령을 사용하는 동안 사용자에게 경고 메시지가
표시됩니다. 라이선스 갱신에 관심이 있는 경우 [contact@tuist.dev](mailto:contact@tuist.dev)로 문의하시기
바랍니다.
<!-- -->
:::

### 기본 환경 구성 {#base-environment-configuration}

| 환경 변수                          | 설명                                                                                                               | 필수  | 기본값                                | 예                                                                   |                                                                                                                                    |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------- | --- | ---------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `TUIST_APP_URL`                | 인터넷에서 인스턴스에 액세스하기 위한 기본 URL입니다.                                                                                  | 예   |                                    | https://tuist.dev                                                   |                                                                                                                                    |
| `tuist_secret_key_base`        | 정보를 암호화하는 데 사용할 키(예: 쿠키의 세션)                                                                                     | 예   |                                    |                                                                     | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `tuist_secret_key_password`    | Pepper로 해시된 비밀번호 생성                                                                                              | 아니요 | `튜리스트_시크릿_키_베이스`                   |                                                                     |                                                                                                                                    |
| `튜이스트_시크릿_키_토큰`                | 랜덤 토큰을 생성하는 비밀 키                                                                                                 | 아니요 | `튜리스트_시크릿_키_베이스`                   |                                                                     |                                                                                                                                    |
| `튜이스트_시크릿_키_암호화`               | 민감한 데이터의 AES-GCM 암호화를 위한 32바이트 키                                                                                 | 아니요 | `튜리스트_시크릿_키_베이스`                   |                                                                     |                                                                                                                                    |
| `TUIST_USE_IPV6`               | `1` 을 입력하면 앱이 IPv6 주소를 사용하도록 구성됩니다.                                                                              | 아니요 | `0`                                | `1`                                                                 |                                                                                                                                    |
| `tuist_log_level`              | 앱에 사용할 로그 수준                                                                                                     | 아니요 | `정보`                               | [로그 수준](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |                                                                                                                                    |
| `튜이스트_구글_앱_이름`                 | GitHub 앱 이름의 URL 버전                                                                                              | 아니요 |                                    | `내 앱`                                                               |                                                                                                                                    |
| `튜이스트_구글_앱_개인키_베이스64`          | 자동 PR 댓글 게시와 같은 추가 기능을 잠금 해제하기 위해 GitHub 앱에 사용되는 base64로 인코딩된 개인 키입니다.                                           | 아니요 | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |                                                                     |                                                                                                                                    |
| `tuist_github_app_private_key` | GitHub 앱에서 자동 PR 댓글 게시와 같은 추가 기능을 잠금 해제하는 데 사용되는 비공개 키입니다. **특수 문자 관련 문제를 방지하려면 Base64로 인코딩된 버전을 사용하는 것이 좋습니다.** | 아니요 | `-----BEGIN RSA...`                |                                                                     |                                                                                                                                    |
| `튜이스트_옵스_사용자_핸들`               | 작업 URL에 액세스할 수 있는 사용자 핸들의 쉼표로 구분된 목록입니다.                                                                         | 아니요 |                                    | `user1,user2`                                                       |                                                                                                                                    |
| `TUIST_WEB`                    | 웹 서버 엔드포인트 사용                                                                                                    | 아니요 | `1`                                | `1` 또는 `0`                                                          |                                                                                                                                    |

### 데이터베이스 구성 {#database-configuration}

데이터베이스 연결을 구성하는 데 사용되는 환경 변수는 다음과 같습니다:

| 환경 변수                                | 설명                                                                                                                                            | 필수  | 기본값       | 예                                                                      |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- | --- | --------- | ---------------------------------------------------------------------- |
| `DATABASE_URL`                       | Postgres 데이터베이스에 액세스하기 위한 URL입니다. URL에는 인증 정보가 포함되어야 합니다.                                                                                     | 예   |           | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `튜이스트_클릭하우스_URL`                     | ClickHouse 데이터베이스에 액세스하기 위한 URL입니다. URL에는 인증 정보가 포함되어야 합니다.                                                                                   | 아니요 |           | `http://username:password@cloud.us-east-2.aws.test.com/production`     |
| `tuist_use_ssl_for_database`         | true이면 [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security)을 사용하여 데이터베이스에 연결합니다.                                                     | 아니요 | `1`       | `1`                                                                    |
| `튜이스트_데이터베이스_풀_크기`                   | 연결 풀에서 계속 열어 둘 연결 수입니다.                                                                                                                       | 아니요 | `10`      | `10`                                                                   |
| `튜이스트_데이터베이스_큐_타겟`                   | 풀에서 체크 아웃된 모든 연결이 큐 간격보다 오래 걸렸는지 확인하는 간격(밀리초)입니다 [(자세한 정보)(https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config).     | 아니요 | `300`     | `300`                                                                  |
| `튜이스트_데이터베이스_큐_인터벌`                  | 풀에서 새 연결 드롭을 시작할지 여부를 결정하는 데 사용하는 큐의 임계값 시간(밀리초)입니다. [(자세한 정보)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | 아니요 | `1000`    | `1000`                                                                 |
| `tuist_clickhouse_flush_interval_ms` | ClickHouse 버퍼 플러시 사이의 시간 간격(밀리초)                                                                                                              | 아니요 | `5000`    | `5000`                                                                 |
| `튜이스트_클릭하우스_최대_버퍼_크기`                | 강제 플러시 전 최대 ClickHouse 버퍼 크기(바이트)                                                                                                             | 아니요 | `1000000` | `1000000`                                                              |
| `튜이스트_클릭하우스_버퍼_풀_크기`                 | 실행할 ClickHouse 버퍼 프로세스 수                                                                                                                      | 아니요 | `5`       | `5`                                                                    |

### 인증 환경 구성 {#authentication-environment-configuration}

ID 공급자(IdP)(https://en.wikipedia.org/wiki/Identity_provider)를 통해 인증을 용이하게 합니다.
이를 활용하려면 선택한 제공업체에 필요한 모든 환경 변수가 서버 환경에 있는지 확인하십시오. **** 변수가 누락되면 Tuist는 해당 공급자를
우회하게 됩니다.

#### GitHub {#github}

GitHub
앱](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)을
사용하여 인증하는 것이 좋지만 [OAuth
앱](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)을
사용할 수도 있습니다. 서버 환경에 GitHub에서 지정한 모든 필수 환경 변수를 포함해야 합니다. 변수가 없으면 Tuist가 GitHub
인증을 간과하게 됩니다. GitHub 앱을 올바르게 설정하려면 다음과 같이 하세요:
- GitHub 앱의 일반 설정에서:
    - `클라이언트 ID` 를 복사하여 `TUIST_GITHUB_APP_CLIENT_ID로 설정합니다.`
    - `클라이언트 비밀` 을 새로 생성하고 복사하여 `TUIST_GITHUB_APP_CLIENT_SECRET으로 설정합니다.`
    - `콜백 URL` 을 `http://YOUR_APP_URL/users/auth/github/callback` 으로 설정합니다.
      `YOUR_APP_URL` 은 서버의 IP 주소일 수도 있습니다.
- 다음 권한이 필요합니다:
  - 리포지토리:
    - 풀 리퀘스트: 읽기 및 쓰기
  - 계정:
    - 이메일 주소: 읽기 전용

`권한 및 이벤트` 의 `계정 권한` 섹션에서 `이메일 주소` 권한을 `읽기 전용` 으로 설정합니다.

그런 다음 Tuist 서버가 실행되는 환경에서 다음 환경 변수를 노출해야 합니다:

| 환경 변수                 | 설명                      | 필수  | 기본값 | 예                                          |
| --------------------- | ----------------------- | --- | --- | ------------------------------------------ |
| `튜이스트_구글_앱_클라이언트_ID`  | GitHub 애플리케이션의 클라이언트 ID | 예   |     | `Iv1.a629723000043722`                     |
| `튜이스트_구글_앱_클라이언트_시크릿` | 애플리케이션의 클라이언트 비밀        | 예   |     | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

OAuth 2](https://developers.google.com/identity/protocols/oauth2)를 사용하여 Google
인증을 설정할 수 있습니다. 이를 위해서는 OAuth 클라이언트 ID 유형의 새 자격 증명을 생성해야 합니다. 자격 증명을 만들 때 애플리케이션
유형으로 "웹 애플리케이션"을 선택하고 이름을 `Tuist` 로 지정한 다음 리디렉션 URI를
`{base_url}/users/auth/google/callback` (여기서 `base_url` 은 호스팅된 서비스가 실행되고 있는
URL)으로 설정합니다. 앱을 생성한 후 클라이언트 ID와 비밀 번호를 복사하여 각각 `GOOGLE_CLIENT_ID` 및
`GOOGLE_CLIENT_SECRET` 환경 변수로 설정합니다.

::: info CONSENT SCREEN SCOPES
<!-- -->
동의 화면을 만들어야 할 수도 있습니다. 이 때 `userinfo.email` 및 `openid` 범위를 추가하고 앱을 내부로 표시하세요.
<!-- -->
:::

#### Okta {#okta}

OAuth 2.0](https://oauth.net/2/) 프로토콜을 통해 Okta로 인증을 활성화할 수 있습니다. 다음
지침<LocalizedLink href="/guides/integrations/sso#okta">에 따라 Okta에서 [앱을 생성](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta)해야 합니다</LocalizedLink>.

Okta 애플리케이션을 설정하는 동안 클라이언트 ID와 비밀번호를 받으면 다음 환경 변수를 설정해야 합니다:

| 환경 변수                        | 설명                                           | 필수  | 기본값 | 예   |
| ---------------------------- | -------------------------------------------- | --- | --- | --- |
| `tuist_okta_1_client_id`     | Okta에 대해 인증할 클라이언트 ID입니다. 이 번호는 조직 ID여야 합니다. | 예   |     |     |
| `tuist_okta_1_client_secret` | Okta에 대한 인증을 위한 클라이언트 비밀                     | 예   |     |     |

`1` 숫자를 조직 ID로 바꿔야 합니다. 일반적으로 1이 되지만 데이터베이스에서 확인하세요.

### 스토리지 환경 구성 {#storage-environment-configuration}

튜이스트는 API를 통해 업로드된 아티팩트를 저장할 스토리지가 필요합니다. **지원되는 스토리지 솔루션 중 하나(** )를 구성해야 Tuist를
효과적으로 운영할 수 있습니다.

#### S3 호환 스토리지 {#s3compliant-storages}

모든 S3 호환 스토리지 공급업체를 사용하여 아티팩트를 저장할 수 있습니다. 스토리지 제공업체와의 통합을 인증하고 구성하려면 다음 환경 변수가
필요합니다:

| 환경 변수                                                   | 설명                                                                              | 필수  | 기본값        | 예                                                             |
| ------------------------------------------------------- | ------------------------------------------------------------------------------- | --- | ---------- | ------------------------------------------------------------- |
| `TUIST_S3_ACCESS_KEY_ID` 또는 `AWS_ACCESS_KEY_ID`         | 스토리지 제공업체에 대해 인증할 액세스 키 ID입니다.                                                  | 예   |            | `아키아이오스푸드`                                                    |
| `TUIST_S3_SECRET_ACCESS_KEY` 또는 `AWS_SECRET_ACCESS_KEY` | 스토리지 제공업체에 대한 인증을 위한 비밀 액세스 키                                                   | 예   |            | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`                    |
| `TUIST_S3_REGION` 또는 `AWS_REGION`                       | 버킷이 위치한 지역                                                                      | 아니요 | `자동`       | `us-west-2`                                                   |
| `TUIST_S3_ENDPOINT` 또는 `AWS_ENDPOINT`                   | 스토리지 제공업체의 엔드포인트                                                                | 예   |            | `https://s3.us-west-2.amazonaws.com`                          |
| `tuist_s3_버킷_이름`                                        | 아티팩트를 저장할 버킷의 이름입니다.                                                            | 예   |            | `튜이스트 아티팩트`                                                   |
| `TUIST_S3_CA_CERT_PEM`                                  | S3 HTTPS 연결을 확인하기 위한 PEM 인코딩된 CA 인증서. 자체 서명 인증서 또는 내부 인증 기관이 있는 에어 갭 환경에 유용합니다. | 아니요 | 시스템 CA 번들  | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `tuist_s3_connect_timeout`                              | 스토리지 공급업체에 연결하기 위한 시간 제한(밀리초)                                                   | 아니요 | `3000`     | `3000`                                                        |
| `tuist_s3_receive_timeout`                              | 스토리지 공급자로부터 데이터를 수신하는 데 걸리는 시간 제한(밀리초)                                          | 아니요 | `5000`     | `5000`                                                        |
| `tuist_s3_pool_timeout`                                 | 스토리지 공급자에 대한 연결 풀의 시간 제한(밀리초)입니다. 시간 초과가 없는 경우 `무한대` 사용                         | 아니요 | `5000`     | `5000`                                                        |
| `tuist_s3_pool_max_idle_time`                           | 풀에 있는 연결의 최대 유휴 시간(밀리초)입니다. ` 무한대` 연결을 무기한으로 유지하려면 다음을 사용하세요.                   | 아니요 | `무한대`      | `60000`                                                       |
| `tuist_s3_pool_size`                                    | 풀당 최대 연결 수                                                                      | 아니요 | `500`      | `500`                                                         |
| `tuist_s3_pool_count`                                   | 사용할 연결 풀의 수                                                                     | 아니요 | 시스템 스케줄러 수 | `4`                                                           |
| `튜이스트_S3_프로토콜`                                          | 스토리지 제공업체에 연결할 때 사용할 프로토콜 (`http1` 또는 `http2`)                                  | 아니요 | `http1`    | `http1`                                                       |
| `tuist_s3_virtual_host`                                 | URL을 버킷 이름을 하위 도메인(가상 호스트)으로 구성해야 하는지 여부                                        | 아니요 | `false`    | `1`                                                           |

::: info AWS authentication with Web Identity Token from environment variables
<!-- -->
스토리지 제공업체가 AWS이고 웹 ID 토큰을 사용하여 인증하려는 경우, 환경 변수 `TUIST_S3_AUTHENTICATION_METHOD`
을 `aws_web_identity_token_from_env_vars` 로 설정하면 Tuist는 기존 AWS 환경 변수를 사용하여 해당 방법을
사용합니다.
<!-- -->
:::

#### Google 클라우드 스토리지 {#google-cloud-storage}
Google 클라우드 스토리지의 경우, [이
문서](https://cloud.google.com/storage/docs/authentication/managing-hmackeys)에 따라
`AWS_ACCESS_KEY_ID` 및 `AWS_SECRET_ACCESS_KEY` 쌍을 얻으세요. ` AWS_ENDPOINT` 는
`https://storage.googleapis.com` 로 설정해야 합니다. 다른 환경 변수는 다른 S3 호환 스토리지와 동일합니다.

### 이메일 구성 {#email-configuration}

Tuist는 사용자 인증 및 거래 알림(예: 비밀번호 재설정, 계정 알림)을 위해 이메일 기능이 필요합니다. 현재 이메일 제공업체로는
**Mailgun(** )만 지원됩니다.

| 환경 변수                  | 설명                                                                       | 필수  | 기본값                                   | 예                         |
| ---------------------- | ------------------------------------------------------------------------ | --- | ------------------------------------- | ------------------------- |
| `튜이스트_메일건_API_키`       | Mailgun 인증을 위한 API 키                                                     | 예*  |                                       | `KEY-1234567890ABCDEF`    |
| `tuist_mailing_domain` | 이메일을 보낼 도메인                                                              | 예*  |                                       | `mg.tuist.io`             |
| `튜이스트_메일링_발신_주소`       | '보낸 사람' 필드에 표시될 이메일 주소입니다.                                               | 예*  |                                       | `noreply@tuist.io`        |
| `튜이스트_메일링_답장_주소`       | 사용자 답장의 답장 수신 주소(선택 사항)                                                  | 아니요 |                                       | `support@tuist.dev`       |
| `튜이스트_스킵_이메일_확인`       | 신규 사용자 등록 시 이메일 확인 건너뛰기. 이 기능을 활성화하면 사용자가 자동으로 확인되며 등록 후 즉시 로그인할 수 있습니다. | 아니요 | `참` 이메일이 구성되지 않은 경우, `거짓` 이메일이 구성된 경우 | `true`, `false`, `1`, `0` |

\* 이메일 구성 변수는 이메일을 보내려는 경우에만 필요합니다. 구성하지 않으면 이메일 확인이 자동으로 건너뜁니다.

::: info SMTP SUPPORT
<!-- -->
현재 일반 SMTP 지원은 제공되지 않습니다. 온프레미스 배포를 위해 SMTP 지원이 필요한 경우
[contact@tuist.dev](mailto:contact@tuist.dev)로 연락하여 요구 사항을 논의하세요.
<!-- -->
:::

::: info AIR-GAPPED DEPLOYMENTS
<!-- -->
인터넷 액세스 또는 이메일 제공업체 구성이 없는 온프레미스 설치의 경우 이메일 확인은 기본적으로 자동으로 건너뜁니다. 사용자는 등록 후 바로
로그인할 수 있습니다. 이메일이 설정되어 있지만 확인을 건너뛰려면 `TUIST_SKIP_EMAIL_CONFIRMATION=true` 을
설정합니다. 이메일이 설정되어 있을 때 이메일 확인을 요구하려면 `TUIST_SKIP_EMAIL_CONFIRMATION=false` 을
설정합니다.
<!-- -->
:::

### Git 플랫폼 구성 {#git-platform-configuration}

Tuist는 <LocalizedLink href="/guides/server/authentication"> Git 플랫폼</LocalizedLink>과 통합하여 풀 리퀘스트에 자동으로 댓글을 게시하는 등의 추가 기능을 제공할 수 있습니다.

#### GitHub {#platform-github}

GitHub
앱](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps)을
만들어야 합니다. OAuth GitHub 앱을 만들지 않았다면 인증용으로 만든 것을 재사용할 수 있습니다. ` 권한 및 이벤트` 의 `리포지토리
권한` 섹션에서 `풀 리퀘스트` 권한을 `읽기 및 쓰기` 로 추가로 설정해야 합니다.

`TUIST_GITHUB_APP_CLIENT_ID` 및 `TUIST_GITHUB_APP_CLIENT_SECRET` 외에 다음 환경 변수가
필요합니다:

| 환경 변수                          | 설명                   | 필수  | 기본값 | 예                          |
| ------------------------------ | -------------------- | --- | --- | -------------------------- |
| `tuist_github_app_private_key` | GitHub 애플리케이션의 비공개 키 | 예   |     | `-----비긴 RSA 개인 키-----...` |

## 로컬 테스트 {#testing-locally}

인프라에 배포하기 전에 로컬 컴퓨터에서 Tuist 서버를 테스트하는 데 필요한 모든 종속성을 포함하는 포괄적인 Docker Compose 구성을
제공합니다:

- 타임스케일DB 2.16 확장이 포함된 PostgreSQL 15(더 이상 사용되지 않음)
- 분석용 ClickHouse 25
- 클릭하우스 키퍼로 조정하기
- S3 호환 스토리지용 MinIO
- 배포 간 영구 KV 스토리지를 위한 Redis(선택 사항)
- 데이터베이스 관리를 위한 PGWEB

::: danger LICENSE REQUIRED
<!-- -->
로컬 개발 인스턴스를 포함하여 Tuist 서버를 실행하려면 법적으로 유효한 `TUIST_LICENSE` 환경 변수가 필요합니다. 라이선스가
필요한 경우 [contact@tuist.dev](mailto:contact@tuist.dev)로 문의하시기 바랍니다.
<!-- -->
:::

**빠른 시작:**

1. 구성 파일을 다운로드합니다:
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. 환경 변수를 구성합니다:
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

4. http://localhost:8080 에서 서버에 액세스하세요.

**서비스 엔드포인트:**
- Tuist 서버: http://localhost:8080
- MinIO 콘솔: http://localhost:9003 (자격 증명: `tuist` / `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb(PostgreSQL UI): http://localhost:8081
- 프로메테우스 지표: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**공통 명령:**

서비스 상태를 확인합니다:
```bash
docker compose ps
# or: podman compose ps
```

로그 보기:
```bash
docker compose logs -f tuist
```

서비스를 중지합니다:
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
  - 클릭하우스 키퍼 구성
- [.env.example](/server/self-host/.env.example) - 환경 변수 파일 예시

## 배포 {#deployment}

공식 Tuist 도커 이미지는 다음 링크에서 확인할 수 있습니다:
```
ghcr.io/tuist/tuist
```

### Docker 이미지 가져오기 {#pulling-the-docker-image}

다음 명령을 실행하여 이미지를 검색할 수 있습니다:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

또는 특정 버전을 가져올 수도 있습니다:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Docker 이미지 배포 {#deploying-the-docker-image}

Docker 이미지의 배포 프로세스는 선택한 클라우드 제공업체와 조직의 지속적인 배포 방식에 따라 달라집니다.
Kubernetes](https://kubernetes.io/)와 같은 대부분의 클라우드 솔루션 및 도구는 Docker 이미지를 기본 단위로
활용하므로 이 섹션의 예는 기존 설정과 잘 맞아야 합니다.

::: warning
<!-- -->
배포 파이프라인에서 서버가 가동 중인지 확인해야 하는 경우, `GET` HTTP 요청을 `/ready` 로 보내고 응답에 `200` 상태 코드를
어설트할 수 있습니다.
<!-- -->
:::

#### Fly {#fly}

Fly](https://fly.io/)에 앱을 배포하려면 `fly.toml` 구성 파일이 필요합니다. 지속적 배포(CD) 파이프라인 내에서
동적으로 생성하는 것을 고려하세요. 아래는 참조용 예제입니다:

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

그런 다음 `fly launch --local-only --no-deploy` 을 실행하여 앱을 실행할 수 있습니다. 이후 배포 시에는 `fly
launch --local-only` 을 실행하는 대신 `fly deploy --local-only` 을 실행해야 합니다. Fly.io는 비공개
Docker 이미지를 가져오는 것을 허용하지 않으므로 `--local-only` 플래그를 사용해야 합니다.


## 프로메테우스 메트릭 {#prometheus-metrics}

Tuist는 자체 호스팅 인스턴스를 모니터링하는 데 도움이 되도록 `/metrics` 에서 Prometheus 지표를 노출합니다. 이러한
메트릭에는 다음이 포함됩니다:

### Finch HTTP 클라이언트 메트릭 {#finch-metrics}

Tuist는 [Finch](https://github.com/sneako/finch)를 HTTP 클라이언트로 사용하며 HTTP 요청에 대한
자세한 메트릭을 노출합니다:

#### 요청 메트릭
- `tuist_prom_ex_finch_request_count_total` - 총 핀치 요청 수(카운터)
  - 레이블: `핀치_이름`, `방법`, `체계`, `호스트`, `포트`, `상태`
- `tuist_prom_ex_finch_request_duration_milliseconds` - HTTP 요청 기간(히스토그램)
  - 레이블: `핀치_이름`, `방법`, `체계`, `호스트`, `포트`, `상태`
  - 버킷 10밀리초, 50밀리초, 100밀리초, 250밀리초, 500밀리초, 1초, 2.5초, 5초, 10초
- `tuist_prom_ex_finch_request_exception_count_total` - 핀치 요청 예외의 총 개수(카운터)
  - 레이블: `핀치_이름`, `방법`, `체계`, `호스트`, `포트`, `종류`, `이유`

#### 연결 풀 대기열 메트릭
- `tuist_prom_ex_finch_queue_duration_milliseconds` - 연결 풀 큐에서 대기하는 데 소요된
  시간(히스토그램)
  - 레이블: `finch_name`, `scheme`, `host`, `port`, `pool`
  - 버킷 1밀리초, 5밀리초, 10밀리초, 25밀리초, 50밀리초, 100밀리초, 250밀리초, 500밀리초, 1초
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - 연결이 사용되기 전에 유휴 상태로 있었던
  시간(히스토그램)
  - 레이블: `finch_name`, `scheme`, `host`, `port`, `pool`
  - 버킷 10밀리초, 50밀리초, 100밀리초, 250밀리초, 500밀리초, 1초, 5초, 10초
- `tuist_prom_ex_finch_queue_exception_count_total` - 핀치 대기열 예외의 총 개수(카운터)
  - 레이블: `핀치_이름`, `체계`, `호스트`, `포트`, `종류`, `이유`

#### 연결 메트릭
- `tuist_prom_ex_finch_connect_duration_milliseconds` - 연결 설정에 소요된 시간(히스토그램)
  - 레이블: `핀치_이름`, `체계`, `호스트`, `포트`, `오류`
  - 버킷 10밀리초, 50밀리초, 100밀리초, 250밀리초, 500밀리초, 1초, 2.5초, 5초
- `tuist_prom_ex_finch_connect_count_total` - 총 연결 시도 횟수(카운터)
  - 레이블: `핀치_이름`, `체계`, `호스트`, `포트`

#### 메트릭 보내기
- `tuist_prom_ex_finch_send_duration_milliseconds` - 요청 전송에 소요된 시간(히스토그램)
  - 레이블: `핀치_이름`, `방법`, `체계`, `호스트`, `포트`, `오류`
  - 버킷 1밀리초, 5밀리초, 10밀리초, 25밀리초, 50밀리초, 100밀리초, 250밀리초, 500밀리초, 1초
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - 전송 전 연결이 유휴 상태로 있었던
  시간(히스토그램)
  - 레이블: `핀치_이름`, `방법`, `체계`, `호스트`, `포트`, `오류`
  - 버킷 1밀리초, 5밀리초, 10밀리초, 25밀리초, 50밀리초, 100밀리초, 250밀리초, 500밀리초

모든 히스토그램 메트릭은 자세한 분석을 위해 `_bucket`, `_sum`, `_count` 변형을 제공합니다.

### 기타 메트릭

Tuist는 Finch 메트릭 외에도 다음에 대한 메트릭을 노출합니다:
- BEAM 가상 머신 성능
- 사용자 지정 비즈니스 로직 메트릭(스토리지, 계정, 프로젝트 등)
- 데이터베이스 성능(Tuist에서 호스팅하는 인프라를 사용하는 경우)

## 운영 {#operations}

Tuist는 `/ops/` 에서 인스턴스를 관리하는 데 사용할 수 있는 유틸리티 세트를 제공합니다.

::: warning Authorization
<!-- -->
`TUIST_OPS_USER_HANDLES` 환경 변수에 핸들이 나열되어 있는 사용자만 `/ops/` 엔드포인트에 액세스할 수 있습니다.
<!-- -->
:::

- **오류(`/ops/errors`):** 애플리케이션에서 발생한 예기치 않은 오류를 볼 수 있습니다. 이 정보는 디버깅하고 무엇이
  잘못되었는지 이해하는 데 유용하며, 문제가 발생하면 이 정보를 공유해 달라고 요청할 수 있습니다.
- **대시보드(`/ops/dashboard`)를 클릭합니다:** 애플리케이션의 성능 및 상태(예: 메모리 사용량, 실행 중인 프로세스, 요청
  수)에 대한 인사이트를 제공하는 대시보드를 볼 수 있습니다. 이 대시보드는 사용 중인 하드웨어가 부하를 처리하기에 충분한지 이해하는 데 매우
  유용할 수 있습니다.
