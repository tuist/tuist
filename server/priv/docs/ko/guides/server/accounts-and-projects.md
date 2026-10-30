---
{
  "title": "계정 및 프로젝트",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Tuist에서 계정과 프로젝트를 생성하고 관리하는 방법을 알아보세요."
}
---
# 계정 및 프로젝트 {#accounts-and-projects}

일부 Tuist 기능은 데이터 영속성을 제공하고 다른 서비스와 상호 작용할 수 있는 서버를 필요로 합니다. 서버와 상호 작용하려면 로컬 프로젝트에 연결할 계정과 프로젝트가 필요합니다.

## 계정 {#accounts}

서버를 사용하려면 계정이 필요합니다. 계정에는 두 가지 유형이 있습니다.

- **개인 계정:** 이러한 계정은 가입 시 자동으로 생성되며, ID 공급자(예: GitHub) 또는 이메일 주소의 첫 부분에서 얻은 핸들로 식별됩니다.
- **조직 계정:** 이러한 계정은 수동으로 생성되며 개발자가 정의한 핸들로 식별됩니다. 조직에서는 다른 구성원을 초대하여 프로젝트에서 협업할 수 있습니다.

[GitHub](https://github.com)에 익숙하다면 개념이 유사합니다. 개인 계정과 조직 계정을 가질 수 있으며, URL을 구성할 때 사용되는 *핸들*로 식별됩니다.

> [!NOTE]
> **CLI 우선**
>
> 계정과 프로젝트를 관리하는 대부분의 작업은 CLI를 통해 수행됩니다. 계정과 프로젝트를 더 쉽게 관리할 수 있는 웹 인터페이스를 개발 중입니다.


<.localized_link href="/cli/organization">`tuist organization`</.localized_link> 하위 명령어를 사용하여 조직을 관리할 수 있습니다. 새 조직 계정을 만들려면 다음을 실행하세요.
```bash
tuist organization create {account-handle}
```

### 조직 멤버십 {#organization-membership}

사용자는 초대, 자동 단일 로그인(SSO) 등록 또는 <.localized_link href="/guides/integrations/authentication/scim">교차 도메인 ID 관리(SCIM) 프로비저닝</.localized_link>을 통해 조직 구성원이 될 수 있습니다.

조직의 ID 공급자로 인증하는 것만으로 멤버십이 부여되지는 않습니다. 조직의 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">단일 로그인(SSO) 등록 정책</.localized_link>에 따라 신뢰할 수 있는 도메인의 사용자가 초대가 필요한지 아니면 자동으로 가입할 수 있는지 결정됩니다.

관리자는 대시보드에서 또는 <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link>를 사용하여 구성원을 초대할 수 있습니다. 초대받은 사람이 수락할 때 `user` 이외의 역할을 부여하려면 `--role admin` 또는 `--role viewer`를 전달하세요.

### 역할 {#roles}

모든 조직 구성원은 다음 세 가지 역할 중 하나를 가집니다.

| 역할 | 권한 |
| --- | --- |
| **관리자** | 사용자가 수행할 수 있는 모든 작업 plus 조직 관리: 구성원 및 초대, 프로젝트, 결제, 토큰, 웹훅 및 설정. |
| **사용자** | 조직의 작업을 읽고 실행합니다: 빌드 및 테스트 실행, 캐시에 쓰기, 미리보기 생성 및 삭제, 테스트 케이스 상태 변경. |
| **뷰어** | 조직의 작업을 읽기만 하며 변경하지 않습니다. 대시보드, 빌드, 테스트 실행, 불안정하고 격리된 테스트, 미리보기, 번들 및 러너 활동은 모두 읽을 수 있습니다. 머신에서 명령을 실행하므로 러너에 인터랙티브 셸 또는 VNC 세션을 연결하는 것은 불가능합니다. |

누군가를 초대할 때 역할을 선택하고, 나중에 대시보드의 **구성원**에서 변경할 수 있습니다. 이렇게 설정된 역할은 이후 로그인으로 덮어쓰이지 않습니다.

## 프로젝트 {#projects}

프로젝트는 원격 프로젝트를 통해 계정과 통합되어야 합니다. GitHub와의 비교를 이어가면, 변경 사항을 푸시하는 로컬 및 원격 리포지토리를 갖는 것과 유사합니다. <.localized_link href="/cli/project">`tuist project`</.localized_link>를 사용하여 프로젝트를 생성하고 관리할 수 있습니다.

프로젝트는 전체 핸들로 식별되며, 이는 조직 핸들과 프로젝트 핸들을 연결한 결과입니다. 예를 들어, 핸들이 `tuist`인 조직과 핸들이 `tuist`인 프로젝트가 있다면 전체 핸들은 `tuist/tuist`가 됩니다.

로컬 프로젝트와 원격 프로젝트 간의 바인딩은 구성 파일을 통해 수행됩니다. 파일이 없다면 `Tuist.swift`에 생성하고 다음 내용을 추가하세요.

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **Tuist 프로젝트 전용 기능**
>
> <.localized_link href="/guides/features/cache/module-cache">모듈 캐싱</.localized_link>과 같은 일부 기능은 Tuist로 관리되는 프로젝트가 필요하다는 점에 유의하세요. Tuist를 사용하여 프로젝트를 관리하지 않으면 이러한 기능을 사용할 수 없습니다.


프로젝트 URL은 전체 핸들을 사용하여 구성됩니다. 예를 들어, 공개된 Tuist 대시보드는 [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist)에서 접근할 수 있으며, 여기서 `tuist/tuist`는 프로젝트의 전체 핸들입니다.
