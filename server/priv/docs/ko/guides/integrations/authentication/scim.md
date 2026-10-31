---
{
  "title": "SCIM 프로비저닝",
  "titleTemplate": ":title | 인증 | 통합 | 가이드 | Tuist",
  "description": "Okta 또는 Microsoft Entra ID로 SCIM 프로비저닝을 구성하는 방법을 알아보세요."
}
---
# SCIM 프로비저닝 {#scim-provisioning}

Tuist는 SCIM 2.0 프로비저닝을 지원하므로, ID 공급자가 조직 구성원을 자동으로 생성, 업데이트 및 프로비저닝 해제할 수 있습니다.

SCIM은 조직 설정의 **인증** 탭에서 구성합니다. SCIM 토큰은 SCIM 액세스 범위로 제한된 조직 소유 계정 토큰이며, 생성 시 한 번만 표시됩니다.

> [!NOTE]
> SCIM은 멤버십과 라이프사이클을 제어합니다. <.localized_link href="/guides/integrations/authentication/sso">단일 사인온</.localized_link>을 대체하지 않습니다. 프로비저닝된 사용자가 ID 공급자를 통해 로그인해야 하는 경우 SSO를 별도로 구성하세요.

프로비저닝된 사용자는 이미 조직 구성원입니다. 동일한 이메일 주소로 로그인하면 해당 멤버십이 공급자 신원 연결에 대한 신뢰를 확립할 수 있습니다. <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">검증된 로그인 이메일 도메인</.localized_link> 및 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">등록 정책</.localized_link>은 아직 프로비저닝되거나 조직에 추가되지 않은 사용자를 제어합니다.

## Okta {#okta}

Okta는 Tuist를 위해 두 개의 별도 애플리케이션을 사용합니다:

- Tuist에 로그인하기 위한 **OIDC 웹 애플리케이션**.
- 사용자와 그룹을 Tuist로 프로비저닝하기 위한 **SCIM 2.0 테스트 앱(헤더 인증)** 애플리케이션.

사용자가 Okta로 로그인해야 하는 경우 먼저 <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link>를 구성한 후, 아래 단계에 따라 SCIM 프로비저닝을 구성하세요.

### 단계 1: Tuist SCIM 토큰 생성 {#okta-step-1}

1. Tuist에서 조직의 **인증** 설정 탭으로 이동하세요.
2. **SCIM 프로비저닝** 섹션에서 **SCIM 엔드포인트 URL**을 복사하세요. `/scim/v2`로 끝나야 합니다.
3. **토큰 생성**을 클릭하세요.
4. 토큰 이름을 지정하세요(예: `Okta`).
5. 생성된 토큰을 복사하세요. Tuist는 토큰을 한 번만 표시합니다.

### 단계 2: Okta SCIM 앱 추가 {#okta-step-2}

1. Okta 관리자 대시보드에서 **애플리케이션 > 애플리케이션 > 앱 카탈로그 탐색**으로 이동하세요.
2. **SCIM 2.0 테스트 앱(헤더 인증)** 을 검색하여 추가하세요.
3. 식별 가능한 이름(예: `Tuist SCIM`)을 지정하세요.
4. SCIM 테스트 앱의 로그인 설정을 완료하세요. Tuist는 이 앱을 로그인에 사용하지 않으며, 로그인은 SSO 가이드의 OIDC 애플리케이션에서 처리됩니다.

### 단계 3: API 통합 구성 {#okta-step-3}

1. SCIM 앱의 **프로비저닝** 탭을 엽니다.
2. **설정 > 통합** 아래에서 **API 통합 구성** 또는 **편집**을 클릭하세요.
3. **API 통합 활성화**를 체크하세요.
4. Tuist **SCIM 엔드포인트 URL**을 Okta의 **기본 URL** 필드에 붙여넣으세요.
5. Tuist SCIM 토큰을 `Bearer ` 접두사가 붙은 **API 토큰**에 붙여넣으세요. 예를 들어, `Bearer tuist_scim_...`입니다. Okta는 이 필드를 `Authorization` 헤더로 전송하며, Tuist는 베어러 토큰을 예상합니다.
6. Okta가 Tuist의 SCIM 그룹을 읽기를 원하면 **그룹 가져오기**를 활성화하세요.
7. **API 자격 증명 테스트**를 클릭하세요. Okta는 통합이 성공적으로 검증되었다고 보고해야 합니다.
8. **저장**을 클릭하세요.

### 단계 4: 프로비저닝 작업 활성화 {#okta-step-4}

1. SCIM 앱의 **프로비저닝** 탭에서 **설정 > 앱으로**를 엽니다.
2. **편집**을 클릭하세요.
3. 다음 항목을 활성화하세요:
   - **사용자 생성**
   - **사용자 속성 업데이트**
   - **사용자 비활성화**
4. **저장**을 클릭하세요.

### 단계 5: 사용자 또는 그룹 할당 {#okta-step-5}

1. SCIM 앱의 **할당** 탭을 엽니다.
2. Tuist로 프로비저닝해야 하는 사용자 또는 그룹을 할당하세요.
3. SSO로 로그인할 수 있어야 하는 경우 동일한 사용자 또는 그룹을 Okta OIDC 애플리케이션에도 할당하세요.
4. Tuist의 **멤버** 탭에서 할당된 사용자가 조직에 표시되는지 확인하세요.

프로비저닝 해제를 테스트하려면 Okta에서 사용자를 할당 해제하거나 비활성화하고, Tuist 조직의 **멤버** 탭에서 해당 사용자가 사라지는지 확인하세요.

### 역할 할당 {#okta-assigning-roles}

Tuist에는 <.localized_link href="/guides/server/accounts-and-projects#roles">역할</.localized_link>이 세 가지 있습니다: `admin`, `user`, `viewer`. Tuist는 역할마다 하나의 SCIM 그룹을 노출합니다: `Tuist Admins`, `Tuist Users`, `Tuist Viewers`. **그룹 푸시**를 사용하여 Okta 그룹을 이들에 매핑하세요:

1. 할당하려는 각 역할에 대해 Okta 그룹을 선택하거나 생성하고, SCIM 앱의 **할당** 탭에서 해당 그룹을 할당하세요.
2. API 통합에서 **그룹 가져오기**가 활성화되어 있는지 확인한 후, SCIM 앱의 **가져오기** 탭을 열고 **지금 가져오기**를 클릭하여 Okta가 Tuist의 그룹을 인식하도록 하세요.
3. SCIM 앱의 **그룹 푸시** 탭을 열고 **그룹 푸시 > 이름으로 그룹 찾기**를 클릭하세요.
4. Okta 그룹을 선택하고, 푸시 작업으로 **그룹 연결**을 선택한 다음 일치하는 Tuist 그룹을 선택하세요. Tuist는 SCIM을 통한 그룹 생성을 지원하지 않으므로 새 그룹을 만드는 대신 기존 그룹에 연결하세요.
5. **저장**을 클릭하고 나머지 역할에 대해 반복하세요.

연결된 그룹에 사용자를 추가하면 해당 역할이 부여됩니다. 그룹에서 제거하면 사용자는 조직이 단일 사인온 멤버를 등록하는 기본 역할로 돌아가며, 관리자가 **설정 > 인증**에서 변경하지 않는 한 이 역할은 `user`입니다. 연결된 그룹에 속하지 않은 사용자도 이 역할을 받습니다. 그룹에서 사용자를 제거해도 조직에서 제거되지는 않습니다. 이를 수행하려면 Okta에서 할당을 해제하거나 비활성화하세요.

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID는 갤러리에 없는 엔터프라이즈 애플리케이션을 통해 Tuist를 프로비저닝합니다. 사용자가 Entra ID로도 로그인해야 하는 경우 먼저 <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link>를 구성하세요.

단일 사인온용으로 등록하는 애플리케이션과 프로비저닝에 사용하는 엔터프라이즈 애플리케이션은 동일할 수 있습니다. 프로비저닝은 엔터프라이즈 애플리케이션 항목에서 구성됩니다.

### 단계 1: Tuist SCIM 토큰 생성 {#entra-step-1}

1. Tuist에서 조직의 **인증** 설정 탭으로 이동하세요.
2. **SCIM 프로비저닝** 섹션에서 **SCIM 엔드포인트 URL**을 복사하세요. `/scim/v2`로 끝나야 합니다.
3. **토큰 생성**을 클릭하세요.
4. 토큰 이름을 지정하세요(예: `Entra ID`).
5. 생성된 토큰을 복사하세요. Tuist는 토큰을 한 번만 표시합니다.

### 단계 2: 프로비저닝 구성 {#entra-step-2}

1. Microsoft Entra 관리자 센터에서 **ID > 애플리케이션 > 엔터프라이즈 애플리케이션**으로 이동하고 Tuist 애플리케이션을 엽니다.
2. **프로비저닝**을 열고 **프로비저닝 모드**를 **자동**으로 설정하세요.
3. **테넌트 URL**을 Tuist SCIM 엔드포인트 URL로 설정하세요.
4. **보안 토큰**을 Tuist SCIM 토큰으로 설정하세요. `Bearer ` 접두사 없이 토큰만 입력하세요. Entra ID가 스키마를 자동으로 추가합니다.
5. **연결 테스트**를 클릭하세요. Entra ID는 제공된 자격 증명이 승인되었다고 보고해야 합니다.
6. 구성을 저장하세요.

### 단계 3: 일치 속성 설정 {#entra-step-3}

1. **매핑** 아래에서 **Microsoft Entra ID 사용자 프로비저닝**을 엽니다.
2. `userPrincipalName` 또는 `mail`가 SCIM `userName` 속성에 매핑되며, 이 속성이 **일치 우선순위 1**에 사용되는지 확인하세요.
3. 존재하는 경우 일치 속성에서 `externalId`를 제거하세요.

Tuist는 `userName`를 사용하여 프로비저닝된 사용자를 일치시킵니다. Entra ID가 `externalId`로 보내는 디렉터리 객체 식별자를 저장하지 않으므로, 해당 속성에 대한 필터는 기존 멤버를 찾지 못하며 프로비저닝 주기 동작이 예측 불가능해질 수 있습니다.

### 단계 4: 그룹 프로비저닝 비활성화 {#entra-step-4}

**매핑** 아래에서 **Microsoft Entra ID 그룹 프로비저닝**을 비활성화로 설정하세요.

Tuist의 SCIM 그룹은 생성할 수 있는 디렉터리 그룹이 아니라 조직 역할당 고정된 그룹이므로, 디렉터리 그룹을 프로비저닝하려는 시도는 실패합니다. 대신 아래 설명대로 역할을 할당하세요.

### 단계 5: 사용자 할당 및 프로비저닝 시작 {#entra-step-5}

1. 애플리케이션의 **사용자 및 그룹** 탭을 열고 Tuist로 프로비저닝해야 하는 사용자 또는 그룹을 할당하세요.
2. **프로비저닝**으로 돌아가서 시작하세요.
3. Tuist의 **멤버** 탭에서 할당된 사용자가 조직에 표시되는지 확인하세요.

Entra ID는 자체 일정에 따라 프로비저닝을 수행하며, 일반적으로 40분마다 실행되므로 멤버가 즉시 표시되지 않습니다. 단일 사용자를 즉시 테스트하려면 **요청 시 프로비저닝**을 사용하세요.

프로비저닝 해제를 테스트하려면 Entra ID에서 사용자의 할당을 해제하거나 비활성화한 후, Tuist 조직의 **멤버** 탭에서 해당 사용자가 사라졌는지 확인하세요.

나중에 프로비저닝 범위를 변경하는 경우(예: **모든 사용자 및 그룹 동기화**에서 **할당된 사용자 및 그룹만 동기화**로 변경), 이후에 **프로비저닝 다시 시작**을 클릭하세요. Entra ID는 재시작 후에만 새 범위를 적용하며, 더 이상 포함되지 않는 사용자의 프로비저닝 해제 작업도 이때 수행됩니다.

### 역할 할당 {#entra-assigning-administrators}

Tuist에는 세 가지 <.localized_link href="/guides/server/accounts-and-projects#roles">역할</.localized_link>이 있습니다: `admin`, `user`, 그리고 `viewer`. Entra ID에서 이를 설정하려면:

1. **앱 등록**에서 Tuist 애플리케이션을 열고 할당하려는 각 Tuist 역할에 대해 앱 역할을 추가하세요. **허용된 멤버 유형**을 **사용자/그룹**으로 설정하고 **값**을 `admin`, `user`, 또는 `viewer`로 설정하세요.
2. 엔터프라이즈 애플리케이션의 **사용자 및 그룹** 탭에서 각 사용자 또는 그룹에 이러한 앱 역할 중 하나를 할당하세요. 사용자는 여러 앱 역할을 보유할 수 있습니다. Tuist는 가장 높은 권한의 역할을 적용합니다. 여기서 `admin`는 `user`보다 우선하며 `user`는 `viewer`보다 우선하므로, 서로 다른 역할에 매핑된 그룹에 속한 사용자는 그중 가장 높은 역할을 받게 됩니다.
3. **프로비저닝 > 매핑** 아래에서 **고급 옵션** 드롭다운을 열고 **대상 사용자 속성 편집**을 선택하세요. **유형**이 `String`로 설정되고 **다중 값**이 체크된 `roles`라는 속성을 추가하세요.
4. **프로비저닝 > 매핑 > Microsoft Entra ID 사용자 프로비저닝** 아래에서 **새 매핑 추가**를 클릭하세요. **매핑 유형**을 **표현식**으로, **표현식**을 `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])`으로, **대상 속성**을 추가한 `roles` 속성으로 설정하세요.
5. 프로비저닝 범위를 **할당된 사용자 및 그룹만 동기화**로 유지하세요. `AssertiveAppRoleAssignmentsComplex`는 **모든 사용자 및 그룹 동기화**와 호환되지 않습니다.

`AssertiveAppRoleAssignmentsComplex`는 사용자가 보유한 모든 앱 역할을 전송하며 제거 사항도 함께 전송하므로, Entra ID에서 역할을 제거하면 사용자는 여전히 보유한 역할 중 가장 높은 권한의 역할로 다운그레이드됩니다. `roles[primary eq "True"].value`에 매핑된 `SingleAppRoleAssignment([appRoleAssignments])`도 작동하지만, 이는 항상 하나의 역할만 전송하며 사용자가 여러 역할을 보유할 때 Entra ID가 어떤 것을 선택할지 보장하지 않습니다.

Entra ID에서 사용자의 앱 역할을 변경하면 다음 프로비저닝 주기에서 Tuist 역할이 업데이트됩니다. 앱 역할 없이 프로비저닝되거나 `admin`, `user`, `viewer` 이외의 값을 가진 사용자는 조직이 단일_sign-on 멤버를 등록하는 기본 역할을 부여받습니다. 관리자가 **설정 > 인증**에서 변경하지 않은 경우 이 기본 역할은 `user`입니다.

## 라이프사이클 동작 {#lifecycle-behavior}

ID 공급자가 사용자를 프로비저닝 애플리케이션에 할당하면, Tuist는 해당 이메일이 이미 알려져 있지 않은 경우 사용자를 생성한 후 조직에 추가합니다. 이메일이 이미 조직 외부의 기존 Tuist 사용자에게 속해 있는 경우, Tuist는 요청을 거부하여 ID 공급자가 해당 조직에서 이미 관리하지 않는 사용자를 주장하는 것을 방지합니다.

ID 공급자가 사용자의 할당을 해제하거나 비활성화하면, Tuist는 사용자 기록과 사용자가 소유한 작업을 보존하면서 조직 역할을 제거합니다. 프로비저닝 해제는 사용자를 전역적으로 비활성화하지 않습니다. 동일한 Tuist 사용자가 다른 조직에 속할 수 있기 때문입니다.

Tuist는 세 가지 합성 SCIM 그룹을 노출합니다: `Tuist Admins`, `Tuist Users`, 그리고 `Tuist Viewers`. 그룹에 멤버를 추가하면 해당 사용자의 조직 역할이 설정됩니다. 현재 역할과 일치하는 그룹에서 멤버를 제거하면 사용자는 등록 역할로 되돌아가며, 멤버십 자체는 사용자가 할당 해제되거나 비활성화될 때만 종료됩니다. ID 공급자는 사용자의 SCIM `roles` 속성을 통해 역할을 설정할 수도 있으며, 값은 `admin`, `user`, 또는 `viewer`입니다. 여러 값을 전송하는 ID 공급자는 그중 가장 높은 권한의 역할을 적용합니다. 여기서 `admin`는 `user`보다 우선하며 `user`는 `viewer`보다 우선합니다.

## 지원되는 SCIM 기능 {#supported-scim-features}

Tuist는 ID 공급자가 라이프사이클 관리에 필요한 SCIM 2.0 엔드포인트를 지원합니다:

- `/Users`에 대한 `POST`, `GET`, `PUT`, `PATCH`, 그리고 `DELETE`.
- `/Groups`에 대한 `GET` 및 `PATCH`.
- `/ServiceProviderConfig`, `/ResourceTypes`, 그리고 `/Schemas`에 대한 SCIM 검색 엔드포인트.
