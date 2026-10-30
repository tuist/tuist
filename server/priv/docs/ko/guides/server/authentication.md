---
{
  "title": "인증",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "CLI에서 Tuist 서버로 인증하는 방법을 알아보세요."
}
---
# 인증 {#authentication}

서버와 상호작용하려면 CLI는 [Bearer 인증](https://swagger.io/docs/specification/authentication/bearer-authentication/)을 사용하여 요청을 인증해야 합니다. CLI는 사용자 계정, 조직 계정 또는 OIDC 토큰을 사용한 인증을 지원합니다.

## 사용자로서 {#as-a-user}

로컬 머신에서 CLI를 사용할 때는 사용자 계정으로 인증하는 것을 권장합니다. 사용자 계정으로 인증하려면 다음 명령어를 실행하세요:

```bash
tuist auth login
```

이 명령어는 웹 기반 인증 흐름을 안내합니다. 인증이 완료되면 CLI는 장기간 유효한 리프레시 토큰과 단기간 유효한 액세스 토큰을 `~/.config/tuist/credentials`에 저장합니다. 디렉터리의 각 파일은 인증 대상 도메인을 나타내며, 기본적으로 `tuist.dev.json`여야 합니다. 해당 디렉터리에 저장된 정보는 민감하므로 **안전하게 보관**하세요.

CLI는 서버에 요청할 때 자격 증명을 자동으로 조회합니다. 액세스 토큰이 만료된 경우, CLI는 리프레시 토큰을 사용하여 새로운 액세스 토큰을 발급받습니다.

> [!NOTE]
> 조직에서 단일 사인온(SSO)을 사용하는 경우, 브라우저에서 엔터프라이즈 로그인 옵션을 선택하고 업무용 이메일 주소를 입력하세요. Tuist는 기존 조직 멤버십 또는 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">검증된 로그인 이메일 도메인</.localized_link>을 통해 제공자를 찾을 수 있습니다.

## OIDC 토큰 {#oidc-tokens}

OpenID Connect(OIDC)를 지원하는 CI 환경에서는 장기간 유효한 비밀 키를 관리할 필요 없이 Tuist가 자동으로 인증할 수 있습니다. 지원되는 CI 환경에서 실행될 때, CLI는 OIDC 토큰 제공자를 자동으로 감지하고 CI에서 제공된 토큰을 Tuist 액세스 토큰으로 교환합니다.

### 지원되는 제공자 {#supported-ci-providers}

Tuist는 다음 CI 제공자를 인식하며, 저장소 연결을 통해 해당 토큰을 프로젝트에 매핑합니다:

- GitHub Actions
- CircleCI
- Bitrise

OpenID Connect 토큰을 발급하는 다른 모든 신원 제공자는 계정 내 현재 및 향후 모든 프로젝트에 대해 한 번 구성하는 [워크로드 신원 신뢰 정책](#workload-identity-trust-policies)을 통해 인증할 수 있습니다. 예를 들어 [Fly.io Machines](#flyio-machines)가 있습니다.

### OIDC 인증 설정 {#setting-up-oidc-authentication}

GitHub Actions, CircleCI 및 Bitrise의 경우:

1. **저장소를 Tuist에 연결**: <.localized_link href="/guides/integrations/gitforge/github">GitHub 통합 가이드</.localized_link>를 따라 GitHub 저장소를 Tuist 프로젝트에 연결하세요.

2. **`tuist auth login` 실행**: 인증이 필요한 명령어 전에 CI 워크플로에서 `tuist auth login`를 실행하세요. CLI는 CI 환경을 자동으로 감지하고 OIDC를 사용하여 인증합니다.

제공자별 구성 예제는 <.localized_link href="/guides/integrations/continuous-integration">지속적 통합 가이드</.localized_link>를 참조하세요.

### 워크로드 신원 신뢰 정책 {#workload-identity-trust-policies}

신뢰 정책을 사용하면 배포 플랫폼, Kubernetes 클러스터 또는 자체 관리 CI 시스템과 같은 다른 신원 제공자의 워크로드가 장기간 유효한 Tuist 비밀 키 없이 프로젝트에 접근할 수 있습니다. 제공자는 다음 조건을 충족해야 합니다:

- 공개 주소에서 HTTPS를 통해 도달 가능해야 합니다. Tuist는 리다이렉트를 따르지 않으며, 자체 호스팅 Tuist 서버에서도 개인 또는 내부 네트워크 주소에는 연결하지 않습니다.
- 비대칭 키(예: `RS256` 또는 `ES256`)로 서명된 JWT를 발급해야 합니다. 서명되지 않은 토큰과 공유 비밀(`HS256` 등)로 서명된 토큰은 거부됩니다.
- 고정 HTTPS URL에서 JSON Web Key Set(JWKS)으로 서명 키를 공개해야 합니다. 응답은 최대 64 KiB이며 최대 20개의 키를 포함해야 합니다.
- 모든 토큰에 만료 시간(`exp`)을 포함해야 합니다.

GitHub Actions, CircleCI 및 Bitrise 발급자는 위의 저장소 기반 흐름을 위해 예약되어 있으며 신뢰 정책에서 사용할 수 없습니다.

> [!NOTE]
> 자체 호스팅 배포의 경우, 워크로드 신원을 구성하거나 작업을 이동하기 전에 데이터베이스 마이그레이션을 적용하고 실행 중인 모든 Tuist 서버 레플리카를 업그레이드하세요. 그다음 CLI 또는 Elixir 통합을 `TUIST_OIDC_TOKEN` 및 `TUIST_OIDC_ACCOUNT`를 지원하는 버전으로 업그레이드하세요. 기존 GitHub Actions, CircleCI 및 Bitrise 작업은 저장소 기반 인증을 계속 사용하며 계정 핸들이 필요하지 않습니다. 프로덕션 작업으로 전환하기 전에 의도된 워크로드에서 단기간 토큰 교환과 캐시 작업을 검증하세요. 새로운 교환을 중단하려면 정책을 제거하세요. 이미 발급된 Tuist 액세스 토큰이 만료될 때까지 최대 1시간이 소요될 수 있습니다. 정책을 삭제해도 해당 토큰이 즉시 폐기되지는 않습니다.

#### 정책 생성 {#create-a-trust-policy}

Tuist 대시보드에서 계정의 **설정** > **인증**을 열고 **워크로드 신원** 섹션을 찾으세요. 계정 관리자(또는 개인 계정 소유자)여야 합니다. 각 계정은 최대 20개의 정책을 가질 수 있습니다. 계정 전체의 CI 접근을 위해 신원을 한 번 구성하면 되며, 프로젝트 선택은 필요하지 않습니다.

**워크로드 신원** 옆의 스위치를 사용하여 정책 양식을 엽니다. 계정에 저장된 신원이 있으면 스위치가 켜진 상태로 시작되며, 저장 후에도 켜진 상태로 유지됩니다. 신원이 없는 계정의 경우 스위치는 꺼진 상태로 시작됩니다. 이 섹션은 조직의 **SCIM 프로비저닝** 아래에 표시됩니다. 양식을 숨겨도 초안이 보존되며 워크로드 인증이 비활성화되지 않습니다. 저장된 신원 카드와 설정 문서 링크는 계속 표시됩니다. 각 카드는 신원의 이름, 발급자 및 JWKS URL, 대상(audience), 정확한 JSON 클레임, 계정 전체 범위 및 생성 시간을 보여줍니다. 카드의 작업을 사용하여 신원을 제거하세요.

아래 필드를 입력하려면 **Custom provider**를 선택하거나, 조직 슬러그와 숫자 형식의 조직 및 애플리케이션 ID로부터 값을 생성하려면 **Fly.io Machines**를 선택하세요. Fly 템플릿은 생성된 발급자, JWKS URL 및 클레임을 **고급 구성**에서 편집할 수 있게 유지합니다. 템플릿이나 도움말 값을 변경해도 수동으로 편집한 필드는 보존됩니다. 발급자, JWKS URL 또는 클레임이 템플릿을 덮어쓰는 경우, Tuist는 **고급 구성**을 확장하고 경고 메시지를 표시하여 저장될 정책을 검토할 수 있게 합니다. Fly 도움말 없이 계속하려면 **Custom provider**로 다시 전환하세요. 템플릿은 구성 값만 채우며 Tuist가 토큰을 검증하는 방식은 변경하지 않습니다.

| 필드 | 설명 |
| --- | --- |
| 이름 | 계정 내에서 고유한 정책 식별 라벨입니다. |
| 발급자 URL | 토큰의 `iss` 클레임입니다. 끝에 슬래시가 있는 경우를 포함하여 정확히 일치해야 합니다. |
| JWKS URL | 제공자의 서명 키에 대한 HTTPS URL입니다. Tuist는 이 URL을 직접 사용하며 제공자의 OpenID Connect 검색 문서를 읽지 않으므로, 제공자의 문서나 `<issuer>/.well-known/openid-configuration`에서 `jwks_uri`을 복사하세요. |
| 대상(Audience) | 토큰이 발급되어야 하는 대상(audience)으로, 기본값은 `tuist`입니다. 토큰의 `aud`는 이 값과 같아야 하며, `aud`가 목록인 경우 이 값을 포함해야 합니다. 다른 서비스를 위해 발행된 토큰이 여기서 재사용되지 않도록 Tuist만 허용하는 값을 사용하세요. |
| 클레임(Claims) | 토큰이 반드시 포함해야 하는 1개에서 10개의 클레임을 가진 JSON 객체로, 예를 들어 `{"sub": "system:serviceaccount:ci:builder"}`와 같습니다. JSON 입력은 최대 8 KiB로 제한됩니다. 값은 문자열, 부호 있는 64비트 정수 또는 불리언이어야 하며 유형을 포함하여 정확히 일치해야 합니다. 예를 들어 `"123"`는 `123`와 일치하지 않습니다. 중첩된 객체, 목록, 그리고 `iss`, `aud`, `exp`, `nbf`, `iat`, `jti`와 같은 시간 또는 토큰 관련 클레임은 허용되지 않습니다. |

각 정책은 개별 프로젝트를 선택하지 않고도 **계정이 소유한 모든 현재 및 향후 프로젝트**에 대한 CI 접근 권한을 부여합니다. 첫 번째 프로젝트를 생성하기 전에 신원을 구성할 수 있습니다. 이는 계정 관리 권한이나 다른 계정에 대한 접근 권한을 부여하지 않습니다.

일치하는 클레임을 가진 토큰을 얻을 수 있는 모든 워크로드는 이러한 모든 프로젝트에 접근할 수 있으므로, 제공자가 보장하고 누구도 재사용할 수 없는 클레임을 선택하세요. 삭제 후 다시 등록하거나 이름을 변경할 수 있는 이름보다는 안정적인 숫자 ID를 선호하세요.

> [!WARNING]
> 공유 신원 제공자에서는 정책을 조직 또는 테넌트 **그리고** 의도된 애플리케이션, 프로젝트 또는 서비스 계정에 바인딩하세요. `main`와 같은 브랜치 이름, `production`와 같은 환경, 또는 일반적인 역할만으로는 신원 경계가 되지 않습니다. 다른 테넌트가 동일한 값을 가진 토큰을 얻을 수 있기 때문입니다. 예를 들어, GitLab.com 정책은 의도된 프로젝트의 안정적인 `project_id`를 포함해야 하며, 단순히 `ref`만 포함해서는 안 됩니다. 일치하는 토큰은 캐시 쓰기를 포함한 계정 전체의 CI 접근 권한을 부여하므로, 관련 없는 워크로드를 신뢰하는 정책은 캐시 포이즈닝을 허용할 수 있습니다.

Tuist는 발급자, 대상(audience), 만료 시간, 유효 시작 시간(최대 60초의 시계 오차 허용) 및 모든 클레임을 확인한 후, 토큰에 서명한 키를 자체 JWKS URL이 보유하고 있는 정책에 대해서만 접근 권한을 부여합니다. 발급된 1시간 유효의 CI 토큰은 계정 전체에 적용되며 프로젝트 ID의 스냅샷이 아닙니다. 이는 발급 이후에 생성되거나 계정으로 이전된 프로젝트를 포함합니다. 프로젝트 승인은 여전히 현재 계정 소유권을 필요로 하므로, 프로젝트를 외부로 이전하면 해당 계정의 토큰 하에서의 접근 권한이 제거됩니다.

#### 워크로드 인증 {#authenticate-a-workload}

1. 정책의 대상(audience)을 사용하여 제공자로부터 신원 토큰을 요청하세요.
2. `TUIST_OIDC_TOKEN`를 해당 토큰으로 설정하고 `TUIST_OIDC_ACCOUNT`를 프로젝트를 소유한 Tuist 계정의 핸들로 설정하세요. 모든 신뢰 정책 교환에는 계정이 필요합니다. 이는 조회 위치만 선택하며 그 자체로는 아무것도 부여하지 않습니다.
3. `tuist auth login`를 실행하세요. Elixir 프로젝트의 경우 대신 `mix tuist.login`를 사용할 수 있으며, `TUIST_TOKEN`이나 유효한 저장된 자격 증명이 없을 때 Elixir 통합이 토큰을 자동으로 교환하도록 할 수 있습니다.

결과적인 Tuist 액세스 토큰은 `ci` 범위 그룹만 가지며 선택된 계정이 소유한 모든 현재 및 향후 프로젝트를 커버합니다. 계정 내 20개 이상의 정책이 동일한 토큰과 일치하거나 두 개 이상의 서로 다른 JWKS URL을 사용하는 경우 교환이 실패합니다.

Tuist는 이러한 세션을 새로 고치지 않습니다. 액세스 토큰은 1시간 후에 만료되며 갱신 토큰이 없습니다. 제공자 신원 토큰은 종종 몇 분 동안만 유효하므로, 오래된 `TUIST_OIDC_TOKEN`를 유지하는 것은 갱신 전략이 아닙니다. 1시간 이상 실행되는 작업의 경우, Tuist 세션이 만료되기 전에 새 신원 토큰을 요청하고 다시 로그인하세요. 정책을 제거하면 새로운 교환이 중단되지만, 이미 발급된 액세스 토큰은 만료될 때까지 유효합니다.

Tuist는 성공적으로 가져온 후 전용 크기 제한 캐시에 제공자의 서명 키를 최대 15분 동안 캐시합니다. 항목은 더 일찍 제거되고 다시 가져올 수 있습니다. 실패한 가져오기는 캐시되지 않습니다. 제공자가 키를 회전하는 경우, 캐시된 집합에 없는 키로 서명된 토큰은 캐시가 만료될 때까지 거부되므로 해당 키로 토큰에 서명하기 최소 15분 전에 새 키를 JWKS에 게시해야 합니다. 키 ID(`kid`)가 없는 토큰은 JWKS에 단일 적합한 서명 키가 포함된 경우에만 허용됩니다. JWKS에 키 ID가 있는 경우, 이는 최대 256바이트의 문자열이어야 합니다.

> [!NOTE]
> `TUIST_OIDC_TOKEN`는 서버 신뢰를 우회하는 방법이 아닌 일반적인 토큰 입력입니다. 이는 CI 제공자 감지보다 우선하며, 서버는 여전히 내장 제공자와 일치하는 신뢰 정책을 가진 신원만 허용합니다. Tuist 자격 증명을 예상하는 `TUIST_TOKEN`에 신원 토큰을 넣지 마세요.

교환이 실패하면 정책의 발급자, 대상(audience) 및 모든 클레임이 토큰과 정확히 일치하는지, JWKS URL이 토큰에 서명한 키를 제공하는지, 정책이 제거되지 않았는지, 그리고 `TUIST_OIDC_ACCOUNT`가 프로젝트를 소유한 계정을 지칭하는지 확인하세요. 어떤 신원이 신뢰되는지 노출되지 않도록 하기 위해, Tuist는 이러한 모든 경우에 대해 동일한 오류를 반환합니다.

### Fly.io Machines {#flyio-machines}

[Fly.io는 OIDC 워크로드 신원을 지원합니다](https://docs.fly.io/reference/openid-connect/). Machine은 Fly API 토큰이나 장기 Tuist 비밀 없이 로컬 `/.fly/api` Unix 소켓에서 단기 서명된 신원 토큰을 요청할 수 있습니다. Fly 토큰은 소스 리포지토리가 아닌 조직과 애플리케이션을 식별하므로, GitHub 리포지토리를 연결하는 대신 신뢰 정책을 사용하세요:

1. Fly Machine 내부에서 발급된 신원 토큰에서 발급자(`iss`), 조직 ID(`org_id`), 및 애플리케이션 ID(`app_id`)를 얻으세요. 발급자는 `https://oidc.fly.io/<organization-slug>`입니다. 조직 또는 앱 이름이 아닌 숫자 ID를 사용하세요.
2. **Fly.io Machines** 템플릿을 사용하여 [신뢰 정책 생성](#create-a-trust-policy)을 수행하고 조직 슬러그와 두 숫자 ID를 입력하세요. 이는 아래 값을 채우고 ID를 문자열로 유지합니다. **Custom provider**를 사용하여 수동으로 입력할 수도 있으며, 클레임에서 ID 주변의 따옴표를 유지하세요.

   | 필드 | 값 |
   | --- | --- |
   | 발급자 URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | 대상(Audience) | `tuist` |
   | 클레임(Claims) | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. Machine 내부에서 `TUIST_OIDC_ACCOUNT`를 프로젝트를 소유한 Tuist 계정 핸들(Fly 조직 슬러그가 아님)로 설정하고, 대상(audience)이 `tuist`인 토큰을 요청한 후, `TUIST_OIDC_TOKEN`를 사용하여 `tuist auth login`에 전달하세요:

```bash
set -euo pipefail
export TUIST_OIDC_ACCOUNT="my-tuist-account"

TUIST_OIDC_TOKEN="$(curl --fail --silent --show-error \
  --unix-socket /.fly/api \
  -X POST http://localhost/v1/tokens/oidc \
  -H 'Content-Type: application/json' \
  --data '{"aud":"tuist"}')"
export TUIST_OIDC_TOKEN

tuist auth login
unset TUIST_OIDC_TOKEN
```

초기 설정 시, 토큰을 환경 변수로 내보낸 후 해제하기 전에 로컬에서 신원 필드만 검사할 수 있습니다. 이는 구성을 위해 클레임을 디코딩하며, Tuist는 인증 중에 서명을 별도로 검증합니다:

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

토큰 자체를 출력하거나 커밋하지 마세요. 승인된 Fly 앱의 모든 Machine은 Tuist 계정의 현재 및 향후 모든 프로젝트에 대해 인증할 수 있습니다. 추가 앱마다 별도의 정책을 생성하세요. Fly 신원 토큰은 약 10분 후에 만료되므로, 장시간 실행되는 Machine에서는 1시간 Tuist 세션이 만료되기 전에 새 토큰을 요청하고 `tuist auth login`를 다시 실행하세요.

### OIDC 토큰 범위 {#oidc-token-scopes}

OIDC 토큰에는 `ci` 범위 그룹이 부여됩니다. GitHub Actions, CircleCI 및 Bitrise의 경우, 이는 리포지토리에 연결된 모든 프로젝트에 대한 액세스를 제공합니다. 워크로드 신원 신뢰 정책의 경우, 이는 프로젝트 생성, 프로젝트 관리, 러너 관리 또는 계정 멤버 관리를 부여하지 않으면서 선택한 계정이 소유한 현재 및 향후 모든 프로젝트에 대한 액세스를 제공합니다. `ci` 범위에 포함되는 내용에 대한 자세한 내용은 [범위 그룹](#scope-groups)을 참조하세요.

> [!TIP]
> **보안 이점**
>
> OIDC 인증은 장기 토큰보다 더 안전합니다. 그 이유는 다음과 같습니다:
> - 회전하거나 관리해야 할 비밀이 없음
> - 토큰의 유효 기간이 짧음
> - 인증이 리포지토리 신원 또는 명시적으로 승인된 워크로드 신원에 연결됨


## Gradle 플러그인 인증 {#gradle-plugin-authentication}

Gradle 플러그인은 Tuist CLI 인증 상태를 사용하며 별도의 로그인 흐름을 정의하지 않습니다. CLI로 한 번 인증하면 플러그인이 해당 자격 증명을 재사용합니다.

`project` 및 `url`를 포함한 프로젝트 및 서버 구성을 위해서는 표준 <.localized_link href="/references/tuist-toml">tuist.toml 참조</.localized_link>를 사용하세요.

로컬 사용 시 다음을 실행하세요:

```bash
tuist auth login
```

CI의 경우 다음 중 하나를 사용하세요:

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 인증</.localized_link> (사용 가능한 경우 권장)
- <.localized_link href="/guides/server/authentication#continuous-integration">계정 토큰 인증</.localized_link> (`TUIST_TOKEN` 통해)

자체 호스팅 Tuist 서버의 경우, `tuist.toml`에 서버 URL을 정의하고(예: `url = "https://tuist.your-company.com"`) 표준 로그인 흐름을 실행하세요. URL은 플러그인이 사용하는 동일한 구성 파일에서 해결됩니다.

인증이 구성된 후 Gradle 캐싱 명령과 작업을 정상적으로 실행하세요.

## 계정 토큰 {#account-tokens}

OIDC를 지원하지 않는 CI 환경이나 권한에 대한 세밀한 제어가 필요한 경우 계정 토큰을 사용할 수 있습니다. 계정 토큰을 사용하면 토큰이 액세스할 수 있는 범위와 프로젝트를 정확히 지정할 수 있습니다.

### 계정 토큰 생성 {#creating-an-account-token}

계정 토큰을 생성하는 가장 쉬운 방법은 대시보드에서 수행하는 것입니다:

1. Tuist 대시보드에서 조직을 엽니다.
2. **설정** > **토큰**으로 이동합니다.
3. **토큰 생성**을 선택합니다.
4. 이름, 선택적 만료 기간, 프로젝트 액세스 및 토큰에 필요한 범위를 선택합니다.
5. 대화 상자를 닫기 전에 생성된 토큰 값을 복사하세요. 토큰 값은 한 번만 표시됩니다.

CLI에서도 계정 토큰을 생성할 수 있으며, 이는 스크립팅이나 자동화에 유용합니다:

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> 토큰이 액세스하려는 프로젝트를 소유한 계정의 핸들로 `account-handle`를 대체하세요. 이는 개인 계정이 아닌 조직 계정일 수 있습니다.

명령어는 다음 옵션을 허용합니다:

| 옵션 | 설명 |
| --- | --- |
| `--scopes` | 필수. 토큰에 부여할 범위의 쉼표로 구분된 목록입니다. |
| `--name` | 필수. 토큰의 고유 식별자(1-32자, 영숫자, 하이픈 및 밑줄만 사용 가능). |
| `--expires` | 선택 사항. 토큰이 만료되어야 하는 시기입니다. `30d`(일), `6m`(개월) 또는 `1y`(년)과 같은 형식을 사용하세요. 지정하지 않으면 토큰은 만료되지 않습니다. |
| `--projects` | 토큰을 특정 프로젝트 핸들로 제한합니다. 지정하지 않으면 토큰은 모든 프로젝트에 액세스할 수 있습니다. |

### 사용 가능한 범위 {#available-scopes}

| 범위 | 설명 |
| --- | --- |
| `account:cache:read` | 계정 범위의 캐시된 바이너리 다운로드 |
| `account:cache:write` | 계정 범위의 캐시된 바이너리 업로드 |
| `account:members:read` | 계정 멤버 읽기 |
| `account:members:write` | 계정 멤버 관리 |
| `account:registry:read` | Swift 패키지 레지스트리에서 읽기 |
| `account:registry:write` | Swift 패키지 레지스트리에 게시 |
| `account:runners:read` | 러너 작업, 워크플로, 프로필 및 볼륨 읽기 |
| `account:runners:write` | 러너 프로필 관리 및 러너 볼륨 지우기 |
| `project:previews:read` | 프리뷰 다운로드 |
| `project:previews:write` | 프리뷰 업로드 |
| `project:admin:read` | 프로젝트 및 설정 읽기 |
| `project:admin:write` | 프로젝트 생성, 업데이트 및 삭제. 프로젝트 생성에는 모든 프로젝트에 액세스할 수 있는 토큰이 필요합니다. |
| `project:cache:read` | 캐시된 바이너리 다운로드 |
| `project:cache:write` | 캐시된 바이너리 업로드 |
| `project:bundles:read` | 번들 보기 |
| `project:bundles:write` | 번들 업로드 |
| `project:tests:read` | 테스트 결과 읽기 |
| `project:tests:write` | 테스트 결과 업로드 |
| `project:builds:read` | 빌드 분석 읽기 |
| `project:builds:write` | 빌드 분석 업로드 |
| `project:runs:read` | 명령 실행 읽기 |
| `project:runs:write` | 명령 실행 생성 및 업데이트 |

### 범위 그룹 {#scope-groups}

범위 그룹은 여러 관련 범위를 단일 식별자로 부여하는 편리한 방법을 제공합니다. 범위 그룹을 사용하면 포함된 개별 범위가 자동으로 확장됩니다.

| 범위 그룹 | 포함된 범위 |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 지속적 통합 {#continuous-integration}

OIDC를 지원하지 않는 CI 환경의 경우, `ci` 범위 그룹으로 계정 토큰을 생성하여 CI 워크플로를 인증하세요. 대시보드에서 토큰을 생성할 때 **CI** 프리셋을 선택합니다.

CLI에서도 동일한 토큰을 생성할 수 있습니다:

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

이는 일반적인 CI 작업(캐시, 프리뷰, 번들, 테스트, 빌드 및 실행)에 필요한 모든 범위를 가진 토큰을 생성합니다. 생성된 토큰을 CI 환경의 비밀로 저장하고 `TUIST_TOKEN` 환경 변수로 설정하세요.

### 계정 토큰 관리 {#managing-account-tokens}

계정 대시보드에서 **설정** > **토큰**을 열어 계정 토큰을 확인하고, 토큰의 범위 및 프로젝트 액세스를 검사하며, 회전 중에 토큰을 취소합니다.

계정의 모든 토큰을 나열하려면:

```bash
tuist account tokens list account-handle
```

이름으로 토큰을 취소하려면:

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### 계정 토큰 사용 {#using-account-tokens}

계정 토큰은 환경 변수 `TUIST_TOKEN`로 정의되어야 합니다:

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **계정 토큰 사용 시기**
>
> 다음과 같은 경우 계정 토큰을 사용하세요:
> - OIDC를 지원하지 않는 CI 환경에서의 인증
> - 토큰이 수행할 수 있는 작업에 대한 세밀한 제어
> - 계정 내 여러 프로젝트에 액세스할 수 있는 토큰
> - 자동으로 만료되는 시간 제한 토큰
