---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 인증 {#authentication}

서버와 상호 작용하려면 CLI에서 [무기명
인증](https://swagger.io/docs/specification/authentication/bearer-authentication/)을
사용하여 요청을 인증해야 합니다. CLI는 사용자 인증, 계정 인증 또는 OIDC 토큰 사용을 지원합니다.

## 사용자로서 {#as-a-user}

컴퓨터에서 로컬로 CLI를 사용할 때는 사용자로 인증하는 것이 좋습니다. 사용자로 인증하려면 다음 명령을 실행해야 합니다:

```bash
tuist auth login
```

이 명령은 웹 기반 인증 절차를 안내합니다. 인증이 완료되면 CLI는 수명이 긴 새로 고침 토큰과 수명이 짧은 접근 토큰을
`~/.config/tuist/credentials` 에 저장합니다. 디렉터리의 각 파일은 인증한 도메인을 나타내며, 기본적으로
`tuist.dev.json` 입니다. 해당 디렉터리에 저장된 정보는 민감한 정보이므로 **안전하게 보관하십시오**.

CLI는 서버에 요청할 때 자동으로 자격 증명을 조회합니다. 액세스 토큰이 만료된 경우 CLI는 새로 고침 토큰을 사용하여 새 액세스 토큰을
얻습니다.

## OIDC 토큰 {#oidc-tokens}

OIDC(OpenID Connect)를 지원하는 CI 환경의 경우, 사용자가 장기 비밀 번호를 관리할 필요 없이 자동으로 인증할 수 있습니다.
지원되는 CI 환경에서 실행할 때 CLI는 자동으로 OIDC 토큰 공급자를 감지하고 CI가 제공한 토큰을 Tuist 액세스 토큰으로 교환합니다.

### 지원되는 CI 제공업체 {#supported-ci-providers}

- GitHub 작업
- CircleCI
- Bitrise

### OIDC 인증 설정 {#setting-up-oidc-authentication}

1. **저장소를 Tuist에 연결**:
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub 통합 가이드</LocalizedLink>에 따라 GitHub 저장소를 Tuist 프로젝트에 연결합니다.

2. **튜이스트 인증 로그인`** 을 실행합니다: CI 워크플로우에서 인증이 필요한 명령 전에 `tuist auth login` 을
   실행하세요. CLI는 자동으로 CI 환경을 감지하고 OIDC를 사용하여 인증합니다.

공급자별 구성 예시는 <LocalizedLink href="/guides/integrations/continuous-integration">연속 연동 가이드</LocalizedLink>를 참조하세요.

### OIDC 토큰 범위 {#oidc-token-scopes}

OIDC 토큰에는 리포지토리에 연결된 모든 프로젝트에 대한 액세스 권한을 제공하는 `ci` 범위 그룹이 부여됩니다. ` ci` 범위에 포함되는
항목에 대한 자세한 내용은 [범위 그룹](#scope-groups)을 참조하세요.

::: tip SECURITY BENEFITS
<!-- -->
OIDC 인증이 수명이 긴 토큰보다 더 안전한 이유는 다음과 같습니다:
- 회전하거나 관리할 비밀이 없습니다.
- 토큰은 수명이 짧고 개별 워크플로 실행으로 범위가 제한됩니다.
- 인증은 리포지토리 ID에 연결됩니다.
<!-- -->
:::

## 계정 토큰 {#account-tokens}

OIDC를 지원하지 않는 CI 환경이나 권한을 세밀하게 제어해야 하는 경우에는 계정 토큰을 사용할 수 있습니다. 계정 토큰을 사용하면 토큰이
액세스할 수 있는 범위와 프로젝트를 정확히 지정할 수 있습니다.

### 계정 토큰 만들기 {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

이 명령은 다음 옵션을 허용합니다:

| 옵션       | 설명                                                                                              |
| -------- | ----------------------------------------------------------------------------------------------- |
| `--범위`   | 필수입니다. 토큰을 부여할 범위를 쉼표로 구분한 목록입니다.                                                               |
| `--이름`   | 필수. 토큰의 고유 식별자(1~32자, 영숫자, 하이픈 및 밑줄만 해당).                                                       |
| `--만료`   | 선택 사항입니다. 토큰이 만료되는 시기. ` 30d` (일), `6m` (개월) 또는 `1y` (년)과 같은 형식을 사용합니다. 지정하지 않으면 토큰이 만료되지 않습니다. |
| `--프로젝트` | 토큰을 특정 프로젝트 핸들로 제한합니다. 지정하지 않으면 토큰이 모든 프로젝트에 액세스할 수 있습니다.                                       |

### 사용 가능한 범위 {#available-scopes}

| 범위             | 설명                   |
| -------------- | -------------------- |
| `계정:멤버:읽기`     | 계정 구성원 읽기            |
| `계정:멤버:쓰기`     | 계정 구성원 관리            |
| `계정:레지스트리:읽기`  | Swift 패키지 레지스트리에서 읽기 |
| `계정:레지스트리:쓰기`  | Swift 패키지 레지스트리에 게시  |
| `프로젝트:미리보기:읽기` | 미리 보기 다운로드           |
| `프로젝트:미리보기:쓰기` | 미리 보기 업로드            |
| `프로젝트:관리자:읽기`  | 프로젝트 설정 읽기           |
| `프로젝트:관리자:쓰기`  | 프로젝트 설정 관리           |
| `프로젝트:캐시:읽기`   | 캐시된 바이너리 다운로드        |
| `프로젝트:캐시:쓰기`   | 캐시된 바이너리 업로드         |
| `프로젝트:번들:읽기`   | 번들 보기                |
| `프로젝트:번들:쓰기`   | 번들 업로드               |
| `프로젝트:테스트:읽기`  | 테스트 결과 읽기            |
| `프로젝트:테스트:쓰기`  | 테스트 결과 업로드           |
| `프로젝트:빌드:읽기`   | 빌드 분석 읽기             |
| `프로젝트:빌드:쓰기`   | 빌드 분석 업로드            |
| `프로젝트:실행:읽기`   | 읽기 명령 실행             |
| `프로젝트:실행:쓰기`   | 명령 실행 만들기 및 업데이트     |

### 범위 그룹 {#scope-groups}

범위 그룹은 하나의 식별자로 여러 개의 관련 범위를 편리하게 부여할 수 있는 방법을 제공합니다. 범위 그룹을 사용하면 해당 그룹에 포함된 모든
개별 범위를 포함하도록 자동으로 확장됩니다.

| 범위 그룹 | 포함된 범위                                                                                |
| ----- | ------------------------------------------------------------------------------------- |
| `ci`  | `프로젝트:캐시:쓰기`, `프로젝트:미리보기:쓰기`, `프로젝트:번들:쓰기`, `프로젝트:테스트:쓰기`, `프로젝트:빌드:쓰기`, `프로젝트:실행:쓰기` |

### 지속적 통합 {#continuous-integration}

OIDC를 지원하지 않는 CI 환경의 경우 `ci` 범위 그룹으로 계정 토큰을 만들어 CI 워크플로우를 인증할 수 있습니다:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

이렇게 하면 일반적인 CI 작업(캐시, 미리보기, 번들, 테스트, 빌드 및 실행)에 필요한 모든 범위가 포함된 토큰이 생성됩니다. 생성된 토큰을
CI 환경에 비밀로 저장하고 `TUIST_TOKEN` 환경 변수로 설정합니다.

### 계정 토큰 관리 {#managing-account-tokens}

계정의 모든 토큰을 나열하려면 다음과 같이 하세요:

```bash
tuist account tokens list my-account
```

토큰을 이름으로 해지하려면 다음과 같이 하세요:

```bash
tuist account tokens revoke my-account ci-cache-token
```

### 계정 토큰 사용 {#using-account-tokens}

계정 토큰은 환경 변수 `TUIST_TOKEN` 으로 정의해야 합니다:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
필요할 때 계정 토큰을 사용하세요:
- OIDC를 지원하지 않는 CI 환경에서의 인증
- 토큰이 수행할 수 있는 작업에 대한 세분화된 제어
- 계정 내에서 여러 프로젝트에 액세스할 수 있는 토큰입니다.
- 자동으로 만료되는 시간 제한 토큰
<!-- -->
:::
