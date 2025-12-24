---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# 계정 및 프로젝트 {#accounts-and-projects}

일부 Tuist 기능에는 데이터의 지속성을 추가하고 다른 서비스와 상호 작용할 수 있는 서버가 필요합니다. 서버와 상호 작용하려면 로컬
프로젝트에 연결하는 계정과 프로젝트가 필요합니다.

## 계정 {#accounts}

서버를 사용하려면 계정이 필요합니다. 계정에는 두 가지 유형이 있습니다:

- **개인 계정:** 이러한 계정은 가입할 때 자동으로 생성되며 ID 공급자(예: GitHub)에서 가져온 핸들 또는 이메일 주소의 첫 번째
  부분으로 식별됩니다.
- **조직 계정입니다:** 이러한 계정은 수동으로 생성되며 개발자가 정의한 핸들로 식별됩니다. 조직을 통해 다른 구성원을 초대하여 프로젝트에서
  공동 작업할 수 있습니다.

깃허브](https://github.com)에 익숙하다면, 개인 계정과 조직 계정을 가질 수 있고 URL을 구성할 때 사용되는 *핸들* 로
식별되는 개념이 비슷하다는 것을 알 수 있습니다.

::: info CLI-FIRST
<!-- -->
계정과 프로젝트를 관리하는 대부분의 작업은 CLI를 통해 이루어집니다. 저희는 계정과 프로젝트를 더 쉽게 관리할 수 있는 웹 인터페이스를 개발
중입니다.
<!-- -->
:::

<LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink> 아래의 하위 명령을 통해 조직을 관리할 수 있습니다. 새 조직 계정을
생성하려면 실행합니다:
```bash
tuist organization create {account-handle}
```

## 프로젝트 {#projects}

Tuist의 프로젝트든 원시 Xcode의 프로젝트든 원격 프로젝트를 통해 계정과 통합해야 합니다. GitHub와 계속 비교하면 변경 사항을
푸시하는 로컬 리포지토리와 원격 리포지토리가 있는 것과 같습니다. <LocalizedLink href="/cli/project">`tuist 프로젝트`</LocalizedLink>를 사용하여 프로젝트를
만들고 관리할 수 있습니다.

프로젝트는 조직 핸들과 프로젝트 핸들을 연결한 결과인 전체 핸들로 식별됩니다. 예를 들어, 조직 핸들이 `tuist` 이고 프로젝트 핸들이
`tuist` 인 경우 전체 핸들은 `tuist/tuist` 입니다.

로컬 프로젝트와 원격 프로젝트 간의 바인딩은 구성 파일을 통해 이루어집니다. 파일이 없는 경우 `Tuist.swift` 에서 생성하고 다음
내용을 추가하세요:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: 경고 튜이스트 프로젝트 전용 기능
<!-- -->
<LocalizedLink href="/guides/features/cache">바이너리 캐싱</LocalizedLink>과 같은 일부 기능에는 Tuist 프로젝트가 있어야 한다는 점에 유의하세요. 원시 Xcode
프로젝트를 사용하는 경우 이러한 기능을 사용할 수 없습니다.
<!-- -->
:::

프로젝트의 URL은 전체 핸들을 사용하여 구성됩니다. 예를 들어, 공개 대시보드인 Tuist의 대시보드는
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist)에서 액세스할 수 있으며, 여기서
`tuist/tuist` 은 프로젝트의 전체 핸들입니다.
