---
title: Why a server?
titleTemplate: :title | Introduction | Server | Tuist
description: Tuist에는 왜 서버가 필요하고 이것이 앱 개발을 확장하는데 어떤 도움이 되는지 배워봅니다.
---

# Why a server? {#why-a-server}

어떤 규모에서는 프로젝트 최적화와 개발자가 프로젝트와 상호 작용하는 방식을 개선하기 위해 시간이 지남에 따라 변하는 데이터를 인지해야 하고, 팀들이 협업하는 데 사용하는 다른 툴과 서비스와의 통합이 필요합니다. 이것은 **데이터를 데이터베이스에 저장하고, 비동기적으로 처리하며, 다른 서비스와 통합할 수 있는 서버**가 있을 때만 가능합니다.

서버의 역할은 다른 시스템에서는 일반적이지만, 앱 개발에서는 일반적이지 않습니다. 여러 팀은 서버의 기능과 유사한 CI 서비스의 기능을 활용하는 오픈 소스에 크게 의존해 왔습니다. 하지만 프로젝트의 복잡성과 작업하는 개발자의 수가 증가하면서 이러한 솔루션의 한계가 더욱 뚜렷해 졌습니다.

우리는 여러 팀이 프로젝트를 확장하기 위해 서버를 설정하고 유지 관리하는 것에 대해 걱정할 필요가 없다고 믿습니다. 그래서 우리는 <LocalizedLink href="/guides/develop/projects">Tuist</LocalizedLink>와 [Xcode 프로젝트](https://developer.apple.com/documentation/xcode/creating-an-xcode-project-for-an-app)를 통합하여 프로젝트와 팀을 확장할 수 있도록 지원하는 서버를 구축했습니다.

> [!TIP] 프로젝트와 워크플로우에 슈퍼파워 부여\
> 서버를 프로젝트와 워크플로우에 부여할 수 있는 슈퍼파워라고 생각합니다. <LocalizedLink href="/guides/develop/build/cache">바이너리 캐싱</LocalizedLink>과 같은 슈퍼파워는 <LocalizedLink href="/guides/develop/projects">Tuist 프로젝트</LocalizedLink>를 요구하지만, 다른 슈퍼파워는 일반 Xcode 프로젝트에서 잘 동작합니다.
