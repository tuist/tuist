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
> SCIM은 멤버십과 라이프사이클을 제어합니다. <.localized_link href="/guides/integrations/authentication/sso">싱글 사인온</.localized_link>을 대체하지 않습니다. 프로비저닝된 사용자가 ID 공급자를 통해 로그인해야 하는 경우 SSO를 별도로 구성하세요.

프로비저닝된 사용자는 이미 조직 구성원입니다. 동일한 이메일 주소로 로그인하면, 해당 멤버십이 공급자 ID 연결에 대한 신뢰를 확립할 수 있습니다. <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">확인된 로그인 이메일 도메인</.localized_link>과 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">등록 정책</.localized_link>은 아직 프로비저닝되지 않았거나 조직에 추가되지 않은 사용자를 제어합니다.

## Okta {#okta}

Okta는 Tuist를 위해 두 개의 별도 애플리케이션을 사용합니다:

- Tuist에 로그인하기 위한 **OIDC 웹 애플리케이션**.
- 사용자와 그룹을 Tuist로 프로비저닝하기 위한 **SCIM 2.0 테스트 앱(헤더 인증)** 애플리케이션.

사용자가 Okta로 로그인해야 하는 경우 먼저 <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link>를 구성한 다음, 아래 단계에 따라 SCIM 프로비저닝을 구성하세요.

### 단계 1: Tuist SCIM 토큰 생성 {#okta-step-1}

1. Tuist에서 조직의 **인증** 설정 탭으로 이동하세요.
2. **SCIM 프로비저닝** 섹션에서 **SCIM 엔드포인트 URL**을 복사하세요. `/scim/v2`로 끝나야 합니다.
3. **토큰 생성**을 클릭하세요.
4. 토큰 이름을 지정하세요(예: `Okta`).
5. 생성된 토큰을 복사하세요. Tuist는 토큰을 한 번만 표시합니다.

### 단계 2: Okta SCIM 앱 추가 {#okta-step-2}

1. Okta 관리자 대시보드에서 **애플리케이션 > 애플리케이션 > 앱 카탈로그 탐색**으로 이동하세요.
2. **SCIM 2.0 테스트 앱(헤더 인증)** 을 검색하고 추가하세요.
3. 인식하기 쉬운 이름(예: `Tuist SCIM`)을 지정하세요.
4. SCIM 테스트 앱의 로그인 설정을 완료하세요. Tuist는 이 앱을 로그인에 사용하지 않으며, 로그인은 SSO 가이드의 OIDC 애플리케이션에서 처리됩니다.

### 단계 3: API 통합 구성 {#okta-step-3}

1. SCIM 앱의 **프로비저닝** 탭을 엽니다.
2. **설정 > 통합** 아래에서 **API 통합 구성** 또는 **편집**을 클릭하세요.
3. **API 통합 활성화**를 체크하세요.
4. Tuist **SCIM 엔드포인트 URL**을 Okta의 **기본 URL** 필드에 붙여넣으세요.
5. Tuist SCIM 토큰을 `Bearer ` 접두사와 함께 **API 토큰**에 붙여넣으세요. 예를 들어, `Bearer tuist_scim_...`. Okta는 이 필드를 `Authorization` 헤더로 보내며, Tuist는 베어러 토큰을 예상합니다.
6. Okta가 Tuist의 SCIM 그룹을 읽도록 하려면 **그룹 가져오기**를 활성화하세요.
7. **API 자격 증명 테스트**를 클릭하세요. Okta는 통합이 성공적으로 확인되었다고 보고해야 합니다.
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
3. SSO로 로그인할 수 있어야 한다면 동일한 사용자 또는 그룹을 Okta OIDC 애플리케이션에도 할당하세요.
4. 할당된 사용자가 조직에 표시되는지 확인하려면 Tuist의 **멤버** 탭을 확인하세요.

프로비저닝 해제를 테스트하려면 Okta에서 사용자를 할당 해제하거나 비활성화한 후, Tuist 조직의 **멤버** 탭에서 해당 사용자가 사라지는지 확인하세요.

### 역할 할당 {#okta-assigning-roles}

Tuist에는 <.localized_link href="/guides/server/accounts-and-projects#roles">역할</.localized_link>이 세 가지 있습니다: `admin`, `user`, `viewer`. Tuist는 역할마다 하나의 SCIM 그룹을 노출합니다: `Tuist Admins`, `Tuist Users`, `Tuist Viewers`. **그룹 푸시**를 사용하여 Okta 그룹을 이에 매핑하세요:

1. 할당하려는 각 역할에 대해 Okta 그룹을 선택하거나 생성하고, SCIM 앱의 **할당** 탭에서 해당 그룹을 할당하세요.
2. API 통합에서 **그룹 가져오기**가 활성화되어 있는지 확인한 후, SCIM 앱의 **가져오기** 탭을 열고 **지금 가져오기**를 클릭하여 Okta가 Tuist의 그룹을 인식하도록 하세요.
3. SCIM 앱의 **그룹 푸시** 탭을 열고 **그룹 푸시 > 이름으로 그룹 찾기**를 클릭하세요.
4. Okta 그룹을 선택하고, 푸시 작업으로 **그룹 링크**를 선택한 후, 일치하는 Tuist 그룹을 선택하세요. Tuist는 SCIM을 통한 그룹 생성을 지원하지 않으므로, 새 그룹을 생성하는 대신 기존 그룹에 링크하세요.
5. **저장**을 클릭하고 나머지 역할에 대해 반복하세요.

링크된 그룹에 사용자를 추가하면 해당 역할이 부여됩니다. 그룹에서 사용자를 제거하면 조직이 단일_sign-on 멤버를 등록하는 기본 역할로 되돌아갑니다. 이는 관리자가 **설정 > 인증**에서 변경하지 않는 한 `user`입니다. 링크된 그룹에 속하지 않은 사용자도 이 역할을 받습니다. 그룹에서 사용자를 제거해도 조직에서 제거되지는 않습니다. 이를 수행하려면 Okta에서 할당을 해제하거나 비활성화하세요.

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID는 갤러리에 없는 엔터프라이즈 애플리케이션을 통해 Tuist를 프로비저닝합니다. 사용자가 Entra ID로도 로그인해야 한다면 먼저 <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link>를 구성하세요.

단일_sign-on용으로 등록하는 애플리케이션과 프로비저닝에 사용하는 엔터프라이즈 애플리케이션은 동일할 수 있습니다. 프로비저닝은 엔터프라이즈 애플리케이션 항목에서 구성됩니다.

### 단계 1: Tuist SCIM 토큰 생성 {#entra-step-1}

1. Tuist에서 조직의 **인증** 설정 탭으로 이동하세요.
2. **SCIM 프로비저닝** 섹션에서 **SCIM 엔드포인트 URL**을 복사하세요. `/scim/v2`로 끝나야 합니다.
3. **토큰 생성**을 클릭하세요.
4. 토큰 이름을 지정하세요(예: `Entra ID`).
5. 생성된 토큰을 복사하세요. Tuist는 토큰을 한 번만 표시합니다.

### 단계 2: 프로비저닝 구성 {#entra-step-2}

1. Microsoft Entra 관리자 센터에서 **Identity > Applications > Enterprise applications**로 이동하고 Tuist 애플리케이션을 엽니다.
2. **Provisioning**을 열고 **Provisioning Mode**를 **Automatic**으로 설정하세요.
3. **Tenant URL**을 Tuist SCIM 엔드포인트 URL로 설정하세요.
4. **Secret Token**을 Tuist SCIM 토큰으로 설정하세요. `Bearer ` 접두사 없이 토큰만 입력하세요. Entra ID가 스킴을 자체적으로 추가합니다.
5. **Test Connection**을 클릭하세요. Entra ID는 제공된 자격 증명이 승인되었다고 보고해야 합니다.
6. 구성을 저장하세요.

### 단계 3: 일치 속성 설정 {#entra-step-3}

1. **Mappings** 아래에서 **Provision Microsoft Entra ID Users**를 엽니다.
2. `userPrincipalName` 또는 `mail`가 SCIM `userName` 속성에 매핑되고, 이 속성이 **Matching precedence 1**에 사용되는지 확인하세요.
3. 존재하는 경우 일치 속성에서 `externalId`을 제거하세요.

Tuist는 `userName`을 기준으로 프로비저닝된 사용자를 일치시킵니다. Entra ID가 `externalId`로 보내는 디렉터리 개체 식별자를 저장하지 않으므로, 해당 속성에 대한 필터는 기존 멤버를 찾지 못하며 프로비저닝 주기 동작이 예측 불가능할 수 있습니다.

### 단계 4: 그룹 프로비저닝 비활성화 {#entra-step-4}

**Mappings** 아래에서 **Provision Microsoft Entra ID Groups**를 비활성화로 설정하세요.

Tuist의 SCIM 그룹은 생성 가능한 디렉터리 그룹이 아닌 조직 역할당 고정된 그룹이므로, 디렉터리 그룹을 프로비저닝하려고 하면 실패합니다. 대신 아래 설명대로 역할을 할당하세요.

### 단계 5: 사용자 할당 및 프로비저닝 시작 {#entra-step-5}

1. 애플리케이션의 **Users and groups** 탭을 열고 Tuist로 프로비저닝해야 하는 사용자 또는 그룹을 할당하세요.
2. **Provisioning**으로 돌아가서 시작하세요.
3. 할당된 사용자가 조직에 표시되는지 확인하려면 Tuist의 **Members** 탭을 확인하세요.

Entra ID는 자체 일정에 따라 프로비저닝하며, 일반적으로 40분마다 실행되므로 멤버가 즉시 표시되지 않습니다. 단일 사용자를 즉시 테스트하려면 **Provision on demand**를 사용하세요.

프로비저닝 해제를 테스트하려면 Entra ID에서 사용자를 할당 해제하거나 비활성화한 후, Tuist 조직의 **Members** 탭에서 해당 사용자가 사라지는지 확인하세요.

나중에 프로비저닝 범위를 변경하는 경우(예: **Sync all users and groups**에서 **Sync only assigned users and groups**로), 이후에 **Restart provisioning**을 클릭하세요. Entra ID는 재시작 후에만 새 범위(더 이상 포함되지 않는 사용자의 프로비저닝 해제 포함)를 적용합니다.

### 역할 할당 {#entra-assigning-administrators}

Tuist에는 <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link> 세 가지가 있습니다: `admin`, `user`, 및 `viewer`. Entra ID에서 이를 설정하려면:

1. **App registrations**에서 Tuist 애플리케이션을 열고 할당하려는 각 Tuist 역할에 대한 앱 역할을 추가하세요. **Allowed member types**을 **Users/Groups**으로, **Value**를 `admin`, `user`, 또는 `viewer`로 설정하세요.
2. 엔터프라이즈 애플리케이션의 **Users and groups** 탭에서 각 사용자 또는 그룹에 해당 앱 역할 중 하나를 할당하세요. 사용자는 여러 앱 역할을 가질 수 있습니다. Tuist는 가장 높은 권한의 역할을 적용합니다. 여기서 `admin`는 `user`보다 우선하고 `user`는 `viewer`보다 우선하므로, 서로 다른 역할에 매핑된 그룹에 속한 사용자는 그중 가장 높은 역할을 받습니다.
3. **Provisioning > Mappings** 아래에서 **Advanced Options** 드롭다운을 열고 **Edit target User attributes**를 선택하세요. **Type**이 `String`로 설정되고 **Multi-Value**가 체크된 상태로 `roles`라는 속성을 추가하세요.
4. **Provisioning > Mappings > Provision Microsoft Entra ID Users** 아래에서 **Add New Mapping**을 클릭하세요. **Mapping type**을 **Expression**으로, **Expression**을 `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])`으로, **Target attribute**를 추가한 `roles` 속성으로 설정하세요.
5. 프로비저닝 범위를 **Sync only assigned users and groups**로 유지하세요. `AssertiveAppRoleAssignmentsComplex`는 **Sync all users and groups**와 호환되지 않습니다.

`AssertiveAppRoleAssignmentsComplex`는 사용자가 보유한 모든 앱 역할을 전송하며 제거 사항도 전송하므로, Entra ID에서 역할을 제거하면 사용자는 여전히 보유 중인 가장 높은 권한의 역할로 다운그레이드됩니다. `roles[primary eq "True"].value`에 매핑된 `SingleAppRoleAssignment([appRoleAssignments])`도 작동하지만, 하나의 역할만 전송하며 사용자가 여러 역할을 보유할 때 Entra ID가 어떤 것을 선택할지는 보장되지 않습니다.

Entra ID에서 사용자의 앱 역할을 변경하면 다음 프로비저닝 주기에서 Tuist 역할이 업데이트됩니다. 앱 역할 없이 프로비저닝되거나 `admin`, `user`, `viewer` 이외의 값으로 프로비저닝된 사용자는 조직이 싱글 사인온 멤버를 등록하는 기본 역할을 받습니다. 관리자가 **Settings > Authentication**에서 변경하지 않았다면 이 역할은 `user`입니다.

## 라이프사이클 동작 {#lifecycle-behavior}

신원 공급자가 프로비저닝 애플리케이션에 사용자를 할당하면, Tuist는 해당 이메일이 아직 알려져 있지 않은 경우 사용자를 생성한 후 조직에 추가합니다. 이메일이 이미 조직 외부의 기존 Tuist 사용자에 속해 있다면, Tuist는 해당 사용자를 추가하고 이에 대해 이메일로 알립니다. 단, 다른 조직의 SCIM 통합으로 계정이 생성된 경우는 예외입니다. 이 경우 Tuist는 요청을 `409`로 거부하여 신원 공급자가 다른 조직이 관리하는 계정을 주장하지 못하도록 합니다.

신원 공급자는 조직이 계정을 단독으로 관리하는 동안에만 사용자의 이메일(`userName`)을 변경할 수 있습니다. 이는 Tuist가 SCIM 통합을 통해 계정을 생성했으며, 그 이후로 사용자가 비밀번호를 설정하지 않았고, 조직의 싱글 사인온 이외의 공급자로 로그인하지 않았으며, 에이전트 등록을 청구하지 않았고, 다른 조직에 가입하지 않았음을 의미합니다. 다른 사용자의 경우, Tuist는 `400` 및 `mutability` SCIM 오류 유형으로 변경을 거부합니다. 동일한 요청으로 전송된 비활성화는 여전히 적용됩니다. Tuist는 또한 다른 조직이 검증한 로그인 도메인이나 tuist.dev의 Tuist 자체 도메인으로 사용자를 생성하거나 이름을 변경하는 것을 거부합니다. 이름 변경 시 사용자가 이전 주소의 소유권을 증명했던 기록은 삭제됩니다.

신원 공급자가 사용자를 할당 해제하거나 비활성화하면, Tuist는 사용자 기록과 사용자가 소유한 작업을 보존하면서 조직 역할을 제거합니다. 프로비저닝 해제는 사용자를 전역적으로 비활성화하지 않습니다. 동일한 Tuist 사용자가 다른 조직에 속할 수 있기 때문입니다.

Tuist는 세 가지 합성 SCIM 그룹을 노출합니다: `Tuist Admins`, `Tuist Users`, 및 `Tuist Viewers`. 그룹에 멤버를 추가하면 해당 조직 역할이 설정됩니다. 현재 역할과 일치하는 그룹에서 멤버를 제거하면 등록 역할로 되돌아갑니다. 멤버십 자체는 사용자가 할당 해제되거나 비활성화될 때만 종료됩니다. 신원 공급자는 사용자의 SCIM `roles` 속성을 통해 `admin`, `user`, 또는 `viewer` 값으로 역할을 설정할 수도 있습니다. 여러 값을 전송하는 신원 공급자는 그중 가장 높은 권한의 값을 적용합니다. 여기서 `admin`는 `user`보다 우선하고 `user`는 `viewer`보다 우선합니다.

## 지원되는 SCIM 기능 {#supported-scim-features}

Tuist는 신원 공급자가 라이프사이클 관리에 필요한 SCIM 2.0 엔드포인트를 지원합니다:

- `/Users`용 `POST`, `GET`, `PUT`, `PATCH`, 및 `DELETE`.
- `/Groups`용 `GET` 및 `PATCH`.
- `/ServiceProviderConfig`, `/ResourceTypes`, 및 `/Schemas`용 SCIM 검색 엔드포인트.
