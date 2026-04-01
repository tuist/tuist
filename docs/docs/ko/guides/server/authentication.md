---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 인증 {#authentication}

서버와 통신하기 위해 CLI는 [베어러
인증](https://swagger.io/docs/specification/authentication/bearer-authentication/)을
사용하여 요청을 인증해야 합니다. CLI는 사용자, 계정 또는 OIDC 토큰을 사용하여 인증하는 기능을 지원합니다.

## 사용자로서 {#as-a-user}

로컬 컴퓨터에서 CLI를 사용할 때는 사용자 계정으로 인증하는 것을 권장합니다. 사용자 계정으로 인증하려면 다음 명령어를 실행해야 합니다:

```bash
tuist auth login
```

이 명령을 실행하면 웹 기반 인증 절차가 진행됩니다. 인증이 완료되면 CLI는 `~/.config/tuist/credentials` 경로에 장기
유효한 리프레시 토큰과 단기 유효한 액세스 토큰을 저장합니다. 이 디렉터리의 각 파일은 인증한 도메인을 나타내며, 기본값은
`tuist.dev.json` 입니다. 이 디렉터리에 저장된 정보는 민감하므로 **반드시 안전하게 보관하십시오**.

CLI는 서버에 요청을 보낼 때 자격 증명을 자동으로 조회합니다. 액세스 토큰이 만료된 경우, CLI는 리프레시 토큰을 사용하여 새로운 액세스
토큰을 가져옵니다.

## OIDC 토큰 {#oidc-tokens}

OIDC(OpenID Connect)를 지원하는 CI 환경의 경우, 사용자가 장기 비밀번호를 관리할 필요 없이 자동으로 인증할 수 있습니다.
지원되는 CI 환경에서 실행할 때 CLI는 자동으로 OIDC 토큰 공급자를 감지하고 CI가 제공한 토큰을 Tuist 액세스 토큰으로 교환합니다.

### 지원되는 CI 제공업체 {#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### OIDC 인증 설정 {#setting-up-oidc-authentication}

1. **리포지토리를 Tuist에 연결하기**:
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub 통합
   가이드</LocalizedLink>를 따라 GitHub 리포지토리를 Tuist 프로젝트에 연결하세요.

2. **`tuist auth login`** 실행: CI 워크플로우에서 인증이 필요한 명령어를 실행하기 전에 `tuist auth login`
   을 실행하십시오. CLI는 CI 환경을 자동으로 감지하고 OIDC를 사용하여 인증합니다.

프로바이더별 구성 예제는
<LocalizedLink href="/guides/integrations/continuous-integration">연속 통합
가이드</LocalizedLink>를 참조하십시오.

### OIDC 토큰 범위 {#oidc-token-scopes}

OIDC 토큰에는 `ci` 범위 그룹이 부여되며, 이를 통해 리포지토리에 연결된 모든 프로젝트에 액세스할 수 있습니다. `ci` 범위에 포함된
내용에 대한 자세한 내용은 [범위 그룹](#scope-groups)을 참조하십시오.

::: tip SECURITY BENEFITS
<!-- -->
OIDC 인증은 장기 유효 토큰보다 더 안전합니다. 그 이유는 다음과 같습니다:
- 회전하거나 관리할 비밀은 없습니다
- 토큰은 수명이 짧으며 개별 워크플로 실행 범위로 제한됩니다
- 인증은 리포지토리 ID와 연동됩니다
<!-- -->
:::

## 계정 토큰 {#account-tokens}

OIDC를 지원하지 않는 CI 환경이나 권한을 세밀하게 제어해야 하는 경우, 계정 토큰을 사용할 수 있습니다. 계정 토큰을 사용하면 토큰이
액세스할 수 있는 범위와 프로젝트를 정확히 지정할 수 있습니다.

### 계정 토큰 생성 {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

이 명령어는 다음 옵션을 지원합니다:

| 옵션           | 설명                                                                                                 |
| ------------ | -------------------------------------------------------------------------------------------------- |
| `--범위`       | 필수. 토큰에 부여할 범위 목록(쉼표로 구분).                                                                         |
| `--name`     | 필수. 토큰을 식별하는 고유한 식별자(1~32자, 영문자와 숫자, 하이픈, 밑줄만 허용).                                                 |
| `--만료일`      | 선택 사항. 토큰의 만료 시점을 지정합니다. `30d` (일), `6m` (개월), 또는 `1y` (년)과 같은 형식을 사용하십시오. 지정하지 않으면 토큰은 만료되지 않습니다. |
| `--projects` | 토큰을 특정 프로젝트 핸들로 제한하십시오. 지정하지 않으면 토큰이 모든 프로젝트에 액세스할 수 있습니다.                                         |

### 사용 가능한 범위 {#available-scopes}

| 적용 범위                    | 설명                   |
| ------------------------ | -------------------- |
| `account:members:read`   | 계정 멤버 읽기             |
| `account:members:write`  | 계정 구성원 관리            |
| `account:registry:read`  | Swift 패키지 레지스트리에서 읽기 |
| `account:registry:write` | Swift 패키지 레지스트리에 게시  |
| `project:previews:read`  | 미리보기 다운로드            |
| `project:previews:write` | 미리보기 업로드             |
| `project:admin:read`     | 프로젝트 설정 읽기           |
| `project:admin:write`    | 프로젝트 설정 관리           |
| `project:cache:read`     | 캐시된 바이너리 다운로드        |
| `project:cache:write`    | 캐시된 바이너리 파일 업로드      |
| `project:bundles:read`   | 번들 보기                |
| `project:bundles:write`  | 번들 업로드               |
| `project:tests:read`     | 테스트 결과 읽기            |
| `project:tests:write`    | 테스트 결과 업로드           |
| `project:builds:read`    | 빌드 분석 읽기             |
| `project:builds:write`   | 빌드 분석 업로드            |
| `project:runs:read`      | 명령어 실행               |
| `project:runs:write`     | 명령 실행 생성 및 업데이트      |

### 범위 그룹 {#scope-groups}

범위 그룹은 하나의 식별자로 여러 개의 관련 범위를 부여할 수 있는 편리한 방법을 제공합니다. 범위 그룹을 사용하면 해당 그룹에 포함된 모든
개별 범위를 포함하도록 자동으로 확장됩니다.

| 범위 그룹 | 포함된 범위                                                                                                                                        |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`  | `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |

### 지속 통합 {#continuous-integration}

OIDC를 지원하지 않는 CI 환경의 경우, `ci` 스코프 그룹을 사용하여 계정 토큰을 생성하고 CI 워크플로를 인증할 수 있습니다:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

이렇게 하면 일반적인 CI 작업(캐시, 미리보기, 번들, 테스트, 빌드 및 실행)에 필요한 모든 범위를 포함하는 토큰이 생성됩니다. 생성된
토큰을 CI 환경의 시크릿으로 저장하고, `TUIST_TOKEN` 환경 변수로 설정하십시오.

### 계정 토큰 관리 {#managing-account-tokens}

계정의 모든 토큰을 나열하려면:

```bash
tuist account tokens list my-account
```

이름으로 토큰을 취소하려면:

```bash
tuist account tokens revoke my-account ci-cache-token
```

### 계정 토큰 사용 {#using-account-tokens}

계정 토큰은 환경 변수 `TUIST_TOKEN` 로 정의되어야 합니다:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
다음과 같은 경우 계정 토큰을 사용하십시오:
- OIDC를 지원하지 않는 CI 환경에서의 인증
- 토큰이 수행할 수 있는 작업에 대한 세밀한 제어
- 계정 내 여러 프로젝트에 액세스할 수 있는 토큰
- 자동으로 만료되는 시간 제한 토큰
<!-- -->
:::
