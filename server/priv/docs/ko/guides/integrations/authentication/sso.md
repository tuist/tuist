---
{
  "title": "싱글 사인온",
  "titleTemplate": ":title | 인증 | 통합 | 가이드 | Tuist",
  "description": "싱글 사인온을 구성하고, 로그인 이메일 도메인을 검증하며, 사용자가 조직에 참여하는 방식을 선택하는 방법을 알아보세요."
}
---
# Single Sign-On {#single-sign-on}

Tuist는 조직의 계정 보안을 강화하기 위해 로그인 옵션으로 Single Sign-On을 제공합니다.

Single Sign-On은 조직 설정의 **Authentication** 탭에서 구성합니다. Google Workspace, Okta, Microsoft Entra ID 및 맞춤형 [OAuth 2.0](https://oauth.net/2/) 제공업체를 지원합니다.

Microsoft Entra ID는 디렉터리 식별자를 기반으로 Tuist가 구성해 주는 OpenID Connect 제공업체입니다. 이 가이드에서 맞춤형 제공업체에 대해 설명하는所有内容(로그인 이메일 도메인 검증 및 등록 포함)도 동일하게 적용됩니다.

> [!NOTE]
> Single Sign-On은 멤버의 인증 방식과 인증된 사용자가 자동으로 가입할 수 있는지 여부를 제어합니다. <.localized_link href="/guides/integrations/authentication/scim">System for Cross-domain Identity Management provisioning</.localized_link>은_identity provider가 조직 멤버를 생성, 업데이트 및 프로비저닝 해제할 수 있는지 여부를 제어합니다. Okta의 경우 대부분의 조직이 둘 다 구성합니다.

## 접근 방식 {#how-access-works}

제공업체 식별, 로그인 검색 및 조직 등록은 별도의 문제입니다:

- **Provider issuer:** 사용자를 인증한 제공업체 조직 또는 권한 부여 서버입니다. Tuist는 연결된 신원을 조회할 때 제공업체, 발급자 및 안정적인 제공업체 사용자 식별자를 결합합니다. Okta의 경우 발급자는 Okta 도메인으로 표시됩니다. Microsoft Entra ID의 경우 디렉터리(테넌트) 식별자에서 파생됩니다. 맞춤형 제공업체의 경우 제공업체 URL로 표시됩니다.
- **Login email domain:** Tuist가 일반 로그인 페이지에서 Okta 또는 맞춤형 제공업체를 검색하는 데 사용하는 이메일 도메인입니다. 검증되면 새 계정 연결 및 자동 등록에 신뢰할 수 있는 이메일 주소를 결정합니다.
- **Enrollment policy:** 신뢰된 도메인의 사용자가 초대가 필요한지 아니면 자동으로 가입할 수 있는지 여부를 결정합니다.
- **Provisioning:** 로그인 흐름과 독립적으로 조직 멤버십을 생성하고 관리합니다.

제공업체 발급자와 로그인 이메일 도메인은 종종 다릅니다. 예를 들어, 회사는 직원 이메일에 `example.com`을 사용할 수 있지만 제공업체 발급자는 `https://login.vendor.example.net`일 수 있습니다. 새로운 Okta 및 맞춤형 제공업체 구성은 이러한 값을 별도로 저장합니다.

### 로그인 이메일 도메인 검증 {#verify-a-login-email-domain}

Okta 및 맞춤형 제공업체 구성은 새 Tuist 계정을 생성하거나 기존 계정을 이메일 주소로 연결하기 전에 검증된 로그인 이메일 도메인이 필요합니다. 도메인이 검증되지 않은 동안에도 멤버는 <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">기존 계정 연결</.localized_link>을 수행할 수 있습니다.

1. **로그인 이메일 도메인**에 `example.com`과 같은 직원 이메일 도메인을 입력하세요.
2. Single Sign-On 구성을 저장합니다.
3. Tuist가 표시한 텍스트 기록을 도메인의 [Domain Name System](https://www.cloudflare.com/learning/dns/dns-records/dns-txt-record/) 구성에 추가합니다.
4. Authentication 설정으로 돌아가 **Verify domain**을 클릭합니다.

검증된 로그인 이메일 도메인은 하나의 Tuist 조직에만 속할 수 있습니다. 도메인을 변경하면 검증이 초기화되며 새 텍스트 기록을 게시해야 합니다. 도메인이 검증될 때까지 자동 등록은 일시 중지됩니다.

Tuist는 매일 텍스트 기록을 다시 확인합니다. 해석이 중단된 기록은 즉시 검증을 초기화하지 않습니다. 도메인은 이를 14일간 유지하며, Authentication 설정에는 **Verification expiring**과 함께 다시 게시할 기록이 표시됩니다. 기록을 게시하고 검증하면 경고가 제거됩니다. 14일 후에도 기록이 여전히 누락된 도메인은 검증되지 않은 상태로 돌아가지며, 제공업체 검색, 신원 연결 및 자동 등록이 다시 검증될 때까지 중단됩니다. 다른 이유로 실패한 조회는 타이머를 갱신하지 않으며 자체적으로 검증을 초기화하지 않습니다. 일일 재확인 도입 전에 검증된 도메인은 재확인되지 않습니다.

Google Workspace는 인증된 신원의 일부로 검증된 Workspace 도메인을 Google에서 제공하므로 별도의 Tuist 검증 단계가 필요하지 않습니다.

### 등록 정책 선택 {#choose-an-enrollment-policy}

Tuist는 두 가지 등록 정책을 지원합니다:

- **초대만:** 사용자는 조직 초대가 필요합니다. Okta 및 맞춤형 제공업체의 경우, 제공업체가 완전히 새로운 Tuist 계정을 생성하려면 로그인 이메일 도메인이 여전히 검증되어야 합니다. 기존 Tuist 계정이 있는 초대받은 사용자는 먼저 초대를 수락한 후 <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">기존 Tuist 계정 연결</.localized_link>에 설명된 대로 제공업체 신원을 연결합니다.
- **자동:** 인증된 이메일이 신뢰된 도메인과 일치하는 사용자는 초대 없이 계정을 생성하거나 연결하고 조직에 가입할 수 있습니다. Google 구성은 Workspace 도메인을 사용합니다. Okta 및 맞춤형 제공업체는 검증된 로그인 이메일 도메인이 필요합니다.

Google 구성은 기본적으로 자동 등록으로 설정됩니다. 새로운 Okta 및 맞춤형 제공업체 구성은 기본적으로 초대만 등록으로 설정됩니다.

**Single Sign-On 강제** 설정은 등록과 독립적입니다. 강제는 기존 조직 멤버가 이메일과 비밀번호를 사용하는 것을 방지하지만 조직 멤버십을 부여하지는 않습니다.

### 등록된 멤버가 받을 역할 선택 {#choose-the-enrollment-role}

자동으로 가입한 멤버는 **등록된 멤버의 역할** 아래에 설정된 <.localized_link href="/guides/server/accounts-and-projects#roles">역할</.localized_link>을 받으며, 관리자가 변경하지 않는 한 기본값은 `user`입니다. 이를 `viewer`로 설정하면 디렉터리의 모든 사람이 로그인할 수 있지만 모두에게 변경 권한을 부여하지는 않습니다.

이 설정은 `admin`로 설정할 수 없으며, 역할 없이 <.localized_link href="/guides/integrations/authentication/scim">SCIM</.localized_link>을 통해 프로비저닝된 멤버와 로그인하는 멤버 모두에게 적용되며, 관리자가 수동으로 설정한 역할을 덮어쓰지 않습니다.

### 기존 Tuist 계정 연결 {#link-an-existing-account}

연결된 제공업체 신원은 계정이 속한 다른 모든 조직을 포함하여 전체 Tuist 계정에 로그인합니다. Okta 및 맞춤형 제공업체의 경우, Tuist는 이메일 주소가 검증된 로그인 이메일 도메인에 있거나 조직의 SCIM 프로비저닝이 계정을 생성했을 때만 기존 계정을 자동으로 연결합니다.

계정 자격 조건을 충족하지 않는 멤버는 직접 신원을 연결합니다:

1. 계정의 일반적인 로그인 방법으로 Tuist에 로그인합니다.
2. Identity Provider(예: 애플리케이션 타일)에서 Tuist를 열거나, Single Sign-On을 강제하는 경우 조직의 프로젝트 중 하나를 엽니다.
3. Tuist가 표시하는 조직과 Identity Provider 계정을 확인한 후 **계정 연결**을 클릭합니다.

로그아웃 상태에서 Single Sign-On으로 시작하는 멤버는 먼저 로그인하라는 요청을 받으며, Tuist는 이후 확인 단계로 돌아갑니다. 연결은 도메인 검증에 의존하지 않으므로, 멤버는 도메인이 검증되기 전에도 Single Sign-On을 사용할 수 있습니다.

### 기존 조직 {#existing-organizations}

모든 Okta 및 맞춤형 제공업체 조직은 검증된 도메인 모델을 사용합니다. 임시 호환 모드는 제거되었습니다.

로그인 이메일 도메인이 검증되지 않은 경우:

- 기존에 연결된 멤버는 계속 로그인할 수 있으며, 기존 SSO 강제는 조직 멤버에게 여전히 적용됩니다.
- 로그인 페이지는 기존 조직 멤버십을 통해서만 제공업체를 발견합니다.
- 자동 등록이 일시 중단되며, 제공업체는 초대가 있더라도 새로운 Tuist 계정을 생성할 수 없습니다.
- 연결되지 않은 멤버는 기존 Tuist 계정에 로그인하고 위에서 설명한 대로 연결을 확인합니다. 조직의 SCIM 프로비저닝으로 생성된 계정은 첫 번째 SSO 로그인 시 여전히 연결할 수 있습니다.
- 새로운 가입자는 이메일 주소가 해당 도메인을 사용한다는 이유만으로 제공업체를 사용해야 하는 것은 아닙니다.

기존에 활성화된 등록 및 강제 설정은 저장된 상태로 유지되며 비활성화할 수 있습니다. 관리자는 도메인이 검증되지 않은 상태에서도 구성을 편집할 수 있지만, 어느 한 설정을 활성화하려면 검증이 필요합니다. 해당 설정이 활성화되면 검증은 일치하는 이메일 주소에 대한 자동 등록을 재개합니다. Google Workspace 동작은 변경되지 않습니다.

**로그인 이메일 도메인**은 조직의 멤버 정보로부터 이미 입력되어 있을 수 있습니다. 값을 확인하고 텍스트 레코드를 게시한 후 **도메인 검증**을 클릭합니다. 일일 재검사를 위해 레코드를 게시된 상태로 유지하세요.

## Google Workspace {#google}

Google Workspace Single Sign-On은 Workspace 도메인을 기준으로 사용자를 인증합니다. 관리자는 일치하는 사용자가 자동으로 가입하도록 허용하거나 초대를 요구할 수 있습니다.

> [!NOTE]
> **필수 조건**
>
> 검증된 도메인이 있는 Google Workspace 조직이 필요합니다. 또한 설정 중인 도메인과 연결된 이메일을 사용하여 Google로 인증해야 합니다.

### 설정 {#google-setup}

1. 조직의 **인증** 설정 탭으로 이동합니다.
2. Single Sign-On을 활성화합니다.
3. 제공업체로 **Google**을 선택합니다.
4. Google Workspace 도메인(예: `example.com`)을 입력합니다.
5. **자동 등록** 또는 초대만 등록을 선택합니다. Google의 경우 자동 등록이 기본적으로 활성화되어 있습니다.
6. 선택적으로 로그인 흐름을 테스트한 후 **Single Sign-On 강제**를 활성화합니다.
7. **변경 사항 저장**을 클릭합니다.

## Okta {#okta}

Okta는 [OpenID Connect](https://openid.net/developers/how-connect-works/)를 사용하여 멤버를 인증합니다. Okta 도메인은 제공업체 발행자를 식별하며, 별도로 검증된 로그인 이메일 도메인은 검색, 새 계정 연결 및 등록을 제어합니다.

Okta가 멤버를 자동으로 생성, 업데이트 또는 프로비저닝 해제하도록 하려면, Single Sign-On이 작동한 후 <.localized_link href="/guides/integrations/authentication/scim#okta">Okta System for Cross-domain Identity Management provisioning</.localized_link>을 구성하세요.

### 단계 1: Okta 애플리케이션 생성 {#okta-step-1}

1. Okta 관리자 대시보드에서 **Applications > Applications > Create App Integration**으로 이동합니다.
2. **OpenID Connect** 및 **Web Application**을 선택합니다.
3. 애플리케이션 이름(예: `Tuist`)을 설정합니다. 선택적으로 [Tuist 로고](https://tuist.dev/images/tuist_dashboard.png)를 업로드합니다.
4. **Sign-in redirect URI**를 인증 설정 페이지에 표시된 값(예: `https://tuist.dev/users/auth/okta/callback`)으로 설정합니다.
5. **Assignments** 아래에서 원하는 액세스 제어를 선택하고 저장합니다.
6. 애플리케이션의 일반 설정에서 **Client ID** 및 **Client Secret**을 복사합니다. **Okta 도메인**(예: `your-company.okta.com`)을 기록해 둡니다.
7. 선택적으로 Okta 대시보드에서 로그인을 허용하려면, General Settings에서 **Edit**을 클릭하고 **Login initiated by**를 **Either Okta or App**으로 변경한 후, **Display application icon to users**를 선택하고 **Initiate login URI**를 인증 설정 페이지에 표시된 값으로 설정합니다.

### 단계 2: Tuist 구성 {#okta-step-2}

1. 조직의 **인증** 설정 탭으로 이동합니다.
2. Single Sign-On을 활성화합니다.
3. 제공업체로 **Okta**을 선택합니다.
4. **Okta 도메인**, **Client ID** 및 **Client Secret**을 입력합니다.
5. **로그인 이메일 도메인** 아래에 직원 이메일 도메인을 입력합니다. 예를 들어, `your-company.okta.com`의 Okta 도메인은 `example.com`의 로그인 이메일 도메인을 가질 수 있습니다.
6. **변경 사항 저장**을 클릭합니다.
7. Tuist에서 표시된 텍스트 기록을 로그인 이메일 도메인에 추가한 후 **도메인 확인**을 클릭합니다.
8. 사용자가 초대가 필요한지 또는 자동 등록이 가능한지 선택한 후 구성을 다시 저장합니다.
9. 선택적으로 로그인 흐름을 테스트한 후 **Single Sign-On 강제**를 활성화합니다.

### 단계 3: Okta 애플리케이션에 사용자 할당 {#okta-step-3}

Okta 애플리케이션을 통해 인증할 수 있어야 하는 사용자 또는 그룹을 할당합니다.

할당은 로그인 흐름에 대한 액세스 권한을 부여하지만, 조직 멤버십은 여전히 등록 정책을 따릅니다. 동일한 사용자가 System for Cross-domain Identity Management를 통해 프로비저닝된 경우, Tuist는 사용자가 처음 로그인할 때 SCIM이 생성한 계정에 Okta 신원을 연결합니다. SCIM이 추가하기 전에 계정이 이미 존재하던 멤버의 경우, 이메일 주소가 검증된 로그인 이메일 도메인에 있거나 로그인된 계정에서 링크를 확인한 후에 연결됩니다.

## Microsoft Entra ID {#microsoft-entra-id}

Microsoft Entra ID는 [OpenID Connect](https://openid.net/developers/how-connect-works/)를 통해 멤버를 인증합니다. Tuist는 디렉터리(테넌트) 식별자에서 권한 부여, 토큰 및 사용자 정보 엔드포인트를 파생하므로, 애플리케이션 자격 증명과 함께 해당 값만 입력하면 됩니다.

Entra ID가 멤버를 자동으로 생성, 업데이트 또는 프로비저닝 해제하도록 하려면, Single Sign-On이 작동한 후 <.localized_link href="/guides/integrations/authentication/scim#microsoft-entra-id">Microsoft Entra ID System for Cross-domain Identity Management provisioning</.localized_link>을 구성하세요.

### 단계 1: Entra 애플리케이션 등록 {#entra-step-1}

1. [Microsoft Entra admin center](https://entra.microsoft.com)에서 **Identity > Applications > App registrations > New registration**으로 이동합니다.
2. 애플리케이션 이름(예: `Tuist`)을 설정합니다.
3. **Redirect URI** 아래에서 **Web** 플랫폼을 선택하고 인증 설정 페이지에 표시된 값(예: `https://tuist.dev/users/auth/oauth2/callback`)을 입력합니다.
4. 애플리케이션을 등록한 후 개요 페이지에서 **Directory (tenant) ID** 및 **Application (client) ID**를 복사합니다.
5. **Certificates & secrets > New client secret**으로 이동하여 비밀을 생성하고 **Value**를 복사합니다. Microsoft는 값을 한 번만 표시하며 모든 클라이언트 비밀에는 만료 날짜가 있으므로, 회전해야 하는 시기를 기록해 둡니다.
6. **API permissions**으로 이동하여 위임된 Microsoft Graph 권한 `openid`, `profile` 및 `email`가 부여되었는지 확인합니다.
7. 선택적으로 멤버가 My Apps 포털에서 로그인 흐름을 시작할 수 있도록 하려면, **Branding & properties** 아래의 **Home page URL**을 인증 설정 페이지에 표시된 값으로 설정합니다.

### 단계 2: Tuist 구성 {#entra-step-2}

1. 조직의 **인증** 설정 탭으로 이동합니다.
2. Single Sign-On을 활성화합니다.
3. 제공업체로 **Microsoft Entra ID**를 선택합니다.
4. **Directory (tenant) ID**, **Client ID** 및 **Client Secret**을 입력합니다.
5. **로그인 이메일 도메인** 아래에 직원 이메일 도메인을 입력합니다. 예를 들어, 사용자가 `first.last@example.com`로 로그인하는 디렉터리는 `example.com`의 로그인 이메일 도메인을 가집니다.
6. **변경 사항 저장**을 클릭합니다.
7. Tuist에서 표시된 텍스트 기록을 로그인 이메일 도메인에 추가한 후 **도메인 확인**을 클릭합니다.
8. 사용자가 초대가 필요한지 또는 자동 등록이 가능한지 선택한 후 구성을 다시 저장합니다.
9. 선택적으로 로그인 흐름을 테스트한 후 **Single Sign-On 강제**를 활성화합니다.

### 단계 3: Entra 애플리케이션에 사용자 할당 {#entra-step-3}

인증할 수 있어야 하는 사용자 또는 그룹을 할당합니다. 애플리케이션이 할당을 요구하도록 구성된 경우, 할당된 사용자만 로그인할 수 있습니다.

할당은 로그인 흐름에 대한 액세스 권한을 부여하지만, 조직 멤버십은 여전히 등록 정책을 따릅니다. 동일한 사용자가 System for Cross-domain Identity Management를 통해 프로비저닝된 경우, Tuist는 사용자가 처음 로그인할 때 SCIM이 생성한 계정에 Entra 신원을 연결합니다. SCIM이 추가하기 전에 계정이 이미 존재하던 멤버의 경우, 이메일 주소가 검증된 로그인 이메일 도메인에 있거나 로그인된 계정에서 링크를 확인한 후에 연결됩니다.

### 이메일 클레임 요구 사항 {#entra-email-claim}

Tuist는 Microsoft Graph 사용자 정보 엔드포인트에서 인증된 사용자의 프로필을 읽으며, 이는 사용자가 사용할 수 있는 이메일 주소가 있을 때만 반환합니다. `mail` 속성이 비어 있는 디렉터리 사용자는 로그인할 수 없습니다. Tuist가 로그인 이메일 도메인과 일치시킬 주소가 없기 때문입니다.

Single Sign-On을 배포하기 전에 할당한 멤버의 디렉터리에 이메일 주소가 입력되어 있는지 확인합니다. 사서함이 없는 온프레미스 Active Directory에서 동기화된 사용자는 이 속성이 누락되는 가장 일반적인 경우입니다.

### 조건부 액세스 및 다중 요소 인증 {#entra-conditional-access}

조건부 액세스 정책, 다중 요소 인증 및 로그인 위험 정책은 권한 부여 요청 중에 평가되므로 다른 Entra 애플리케이션과 마찬가지로 Tuist 애플리케이션에도 적용됩니다. 추가적인 Tuist 구성은 필요하지 않습니다.

## Custom OAuth 2.0 제공업체 {#custom-oauth-2-provider}

Custom OAuth 2.0 제공업체를 사용하면 조직이 Google Workspace나 Okta 이외의 신원 서비스를 사용할 수 있습니다. 제공업체의 사용자 정보 엔드포인트는 안정적인 사용자 식별자와 이메일 주소를 반환해야 합니다.

1. 제공업체에서 OAuth 2.0 웹 애플리케이션을 생성합니다.
2. Tuist의 인증 설정에 표시된 값으로 **로그인 리디렉션 URI**와 선택적 **로그인 시작 URI**를 설정합니다.
3. Tuist에서 Single Sign-On을 활성화하고 **OAuth2**를 선택합니다.
4. 제공업체 URL, 권한 부여 엔드포인트, 토큰 엔드포인트, 사용자 정보 엔드포인트, 클라이언트 식별자 및 클라이언트 시크릿을 입력합니다.
5. **로그인 이메일 도메인**을 입력하고 저장합니다. 이는 직원 이메일 도메인이며 제공업체 URL이 아닙니다.
6. Tuist가 표시한 텍스트 레코드를 로그인 이메일 도메인에 추가한 후 **도메인 확인**을 클릭합니다.
7. 초대 전용 또는 자동 등록 중 하나를 선택하고 구성을 저장합니다.
8. 선택적으로 **Single Sign-On 강제 적용**을 활성화하기 전에 로그인을 테스트합니다.

제공업체 URL은 신원을 발급 제공업체로 제한합니다. 검증된 로그인 이메일 도메인은 사용자를 연결하거나 등록할 때 Tuist가 신뢰할 수 있는 이메일 주소를 결정합니다.

## 명령줄 구성 {#command-line-configuration}

명령줄 인터페이스는 Google Workspace나 Okta를 구성하고 등록 정책을 선택할 수 있습니다. 예를 들어:

```bash
tuist organization update sso example \
  --provider okta \
  --organization-id your-company.okta.com \
  --enrollment-policy invitation-only
```

Microsoft Entra ID와 Custom 제공업체는 명령줄 대신 조직의 인증 설정에서 구성됩니다.

`--organization-id` 값은 제공업체 조직을 식별합니다. 이는 로그인 이메일 도메인이 아닙니다. 새 Okta 사용자를 등록하기 전에 조직의 인증 설정에서 로그인 이메일 도메인을 추가하고 검증합니다.

## 문제 해결 {#troubleshooting}

### 기존 멤버는 로그인할 수 있지만 새 사용자는 불가능함 {#existing-members-can-sign-in-but-new-users-cannot}

Okta 및 Custom 제공업체 구성의 경우 로그인 이메일 도메인이 검증되었는지 확인합니다. 그런 다음 사용자를 초대하거나 자동 등록을 활성화합니다.

### Single Sign-On이 먼저 로그인을 요청함 {#single-sign-on-asks-you-to-log-in-first}

Tuist 계정의 이메일 주소가 조직의 검증된 로그인 이메일 도메인에 없거나 도메인이 아직 검증되지 않았으므로 Tuist가 제공업체 신원을 자동으로 연결하지 않습니다. 평소 사용하는 로그인 방법으로 로그인하고 <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">기존 Tuist 계정 연결</.localized_link>에 설명된 대로 링크를 확인합니다.
### Tuist가 이메일 주소에 대한 조직을 찾을 수 없음 {#tuist-cannot-find-an-organization-for-an-email-address}

사용자가 예상된 직원 이메일 주소를 입력했으며 해당 도메인이 검증된 로그인 이메일 도메인과 정확히 일치하는지 확인합니다. 기존 멤버는 현재 조직 멤버십을 통해 발견될 수도 있습니다.

### 도메인 검증이 대기 중임 {#domain-verification-remains-pending}

텍스트 레코드 이름과 값이 Tuist에 표시된 값과 정확히 일치하는지 확인합니다. DNS 변경 사항이 전파되는 데 시간이 걸릴 수 있으므로 레코드가 공개된 후 검증을 다시 시도합니다.

### 제공업체 변경 후 로그인 중단됨 {#sign-in-stopped-after-changing-the-provider}

강제 적용을 활성화하기 전에 새 제공업체 구성을 확인하고, 로그인 이메일 도메인을 검증하며, 로그인 흐름을 테스트합니다.
