---
title: Accounts and projects
titleTemplate: :title | Server | Guides | Tuist
description: Tuist에서 계정과 프로젝트를 생성하고 관리하는 방법을 배워봅니다.
---

# Accounts and projects {#accounts-and-projects}

Some Tuist features require a server which adds persistence of data and can interact with other services. To interact with the server, you need an account and a project that you connect to your local project.

## 계정 {#accounts}

서버를 사용하려면 계정이 필요합니다. 계정은 두 가지 타입이 있습니다:

- **개인 계정:** 이러한 계정은 회원 가입 시 자동으로 생성되고 아이디는 제공하는 서비스 (예: GitHub) 에서 얻거나 이메일 주소의 첫번째 부분으로 설정됩니다.
- **조직 계정:** 이러한 계정은 수동으로 생성되고 개발자가 지정한 아이디로 설정합니다. 조직 계정은 프로젝트의 협업자로 멤버를 추가할 수 있습니다.

[GitHub](https://github.com)에 익숙하다면 개인 계정과 조직 계정을 가질 수 있고 이 계정들은 URL을 구성할 때 식별자로 사용된다는 개념과 유사합니다.

> [!NOTE] CLI-FIRST\
> 계정과 프로젝트를 관리하기 위한 동작은 대부분 CLI를 통해서 수행됩니다. 우리는 계정과 프로젝트를 쉽게 관리하기 위한 웹 인터페이스를 개발 중입니다.

<LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink> 하위 명령어를 통해 조직을 관리할 수 있습니다. 새로운 조직 계정을 생성하기 위해 다음과 같이 수행합니다:

```bash
tuist organization create {account-handle}
```

## 프로젝트 {#projects}

Tuist 프로젝트든 Xcode 프로젝트든 원격 프로젝트를 통해 계정과 통합되어야 합니다. GitHub와 계속 비교해 보면, 변경 사항을 푸시할 수 있는 로컬 리포지토리와 원격 리포지토리와 비슷합니다. 프로젝트를 생성하고 관리하기 위해 <LocalizedLink href="/cli/project">`tuist project`</LocalizedLink>를 사용할 수 있습니다.

프로젝트는 조직 식별자와 프로젝트 식별자를 결합한 전체 식별자로 식별됩니다. 예를 들어, `tuist`라는 식별자를 가진 조직과 `tuist`라는 식별자를 가지는 프로젝트가 있다면, 전체 식별자는 `tuist/tuist` 입니다.

로컬 프로젝트와 원격 프로젝트 간의 연결은 구성 파일을 통해 이루어집니다. 아무런 구성 파일이 없다면 `Tuist.swift` 파일을 생성하고 다음의 내용을 추가합니다:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!IMPORTANT] TUIST 프로젝트 전용 기능\ <LocalizedLink href="/guides/features/build/cache">바이너리 캐싱</LocalizedLink>과 같은 기능은 Tuist 프로젝트가 있어야 사용할 수 있습니다. Xcode 프로젝트를 사용한다면 해당 기능을 사용할 수 없습니다.

프로젝트 URL은 전체 식별자를 사용하여 구성됩니다. 예를 들어, Tuist 대시보드는 프로젝트의 전체 식별자가 `tuist/tuist`라면 [cloud.tuist.io/tuist/tuist](https://cloud.tuist.io/tuist/tuist)으로 접근할 수 있습니다.
