---
title: Principles
titleTemplate: :title - Tuist에 기여하기
description: 이 문서는 Tuist의 개발을 위한 원칙을 설명합니다.
---

# Principles {#principles}

이 페이지는 Tuist의 디자인과 개발의 기둥이 되는 원칙을 설명합니다. 이것은 프로젝트와 함께 발전하고 프로젝트 기반과 잘 부합하는 지속 가능한 성장을 보장하기 위한 것입니다.

## 기본 규칙 {#default-to-conventions}

Tuist가 존재하는 이유 중에 하나는 Xcode가 규칙이 약해 확장과 유지 보수가 어려운 복잡한 프로젝트를 생성하기 때문입니다. 이런 이유로 Tuist는 간단하고 철저하게 설계된 규칙을 기본적으로 사용합니다. **개발자는 규칙을 제외할 수 있지만, 그것은 자연스럽지 않습니다.**

예를 들어, 제공된 인터페이스를 사용하여 타겟과의 의존성을 정의하는 규칙이 있습니다. 이를 통해 Tuist는 제대로 된 구성으로 프로젝트가 생성되도록 보장합니다. 개발자는 빌드 설정으로 의존성을 정의할 수 있지만, 이것은 암묵적으로 정의하므로 일부 규칙을 따라야 하는 `tuist graph` 또는 `tuist cache` 와 같은 Tuist 기능의 규칙에 어긋납니다.

규칙을 따라야 하는 이유는 개발자를 대신해서 많은 결정을 해주면 개발자는 앱의 기능을 만드는데 더 집중할 수 있기 때문입니다. 많은 프로젝트에서 규칙이 없다면, 이전에 결정한 사항과 일관성 없는 결정을 하게되고 결과적으로 관리하기 어렵게 됩니다.

## Manifest는 진실 공급원 {#manifests-are-the-source-of-truth}

여러 층을 가지는 구성과 그 구성 간의 계약은 프로젝트 설정을 이해하고 유지하기 어렵게 만듭니다. 일반적인 프로젝트를 생각해 봅시다. 프로젝트의 정의는 `.xcodeproj ` 디렉토리, 스크립트 (예: `Fastfiles `) 에 CLI, 파이프라인에 CI 로직이 있습니다. 이 세 가지 층은 서로의 계약을 유지해야 합니다. _How often have you been in a situation where you changed something in your projects, and then a week later you realized that the release scripts broke?_

우리는 단일 진실 공급원 인 Manifest 파일로 이것을 단순하게 변경할 수 있습니다. 이 파일은 개발자가 Xcode 프로젝트를 생성하는데 필요한 정보를 Tuist에 제공합니다. 게다가, 로컬 또는 CI 환경에서 프로젝트를 빌드하기 위한 표준 명령어를 사용할 수 있습니다.

**Tuist는 복잡성을 관리하고 가능한 프로젝트를 명확하게 설명하기 위해 간단하고 안전하며 즐거운 인터페이스를 제공해야 합니다.**

## 암묵적인 것을 명시적으로 만들기 {#make-the-implicit-explicit}

Xcode는 암묵적 구성을 제공합니다. 그 좋은 예는 암묵적으로 정의된 의존성을 유추하는 것입니다. 암묵성은 구성이 간단한 작은 프로젝트에서는 좋지만, 프로젝트가 커질 수록 느리거나 이상한 동작을 야기시킵니다.

Tuist는 Xcode의 암묵적 동작에 대해 명시적으로 API를 제공해야 합니다. 또한, Xcode 암묵적 정의를 지원하지만 개발자가 명시적 접근방식을 선택하도록 구현해야 합니다. Xcode 암묵성과 복잡성을 모두 제공하면 Tuist 채택이 용이해지고, 나중에 팀은 암묵성을 제거하는 시간을 할애할 수 있습니다.

이것의 좋은 예는 의존성 정의입니다. 개발자는 Build Settings과 Build Phases에서 의존성 정의를 할 수 있지만, Tuist는 더 좋은 API를 제공합니다.

**API를 명시적으로 설계하면 그렇지 않은 프로젝트에서 불가능한 일부 검사와 최적화를 Tuist가 수행할 수 있습니다.** 게다가, 의존성 그래프를 표현하는 `tuist graph` 또는 바이너리로 모든 타겟을 캐시하는 `tuist cache` 와 같은 기능을 사용할 수 있습니다.

> [!팁]
> Xcode의 기능을 이식해 달라는 요청은 간단하고 명확한 API를 통해 개념을 단순화할 수 있는 기회로 여겨야 합니다.

## 단순함을 유지 {#keep-it-simple}

Xcode 프로젝트를 확장할 때 주요 과제 중 하나는 **Xcode가 사용자에게 많은 복잡성을 보인다는** 사실에서 비롯됩니다. 이로 인해, 팀은 높은 버스 팩터를 가지고 팀에 일부 인원만 프로젝트와 빌드 시스템에서 발생하는 오류를 이해합니다. 이러한 상황은 팀이 소수 인원에 의지하게 되므로 안좋은 상황입니다.

Xcode는 훌륭한 툴이지만, 수 년간의 개선과 새로운 플랫폼, 그리고 프로그래밍 언어가 반영되면서 단순함을 유지하는데 어려움을 겪었습니다.

Tuist는 간단한 업무는 재미와 동기부여를 하기 때문에 단순함을 유지해야 합니다. 어느 누구도 컴파일 마지막에 발생한 오류를 디버깅 하거나 단말에 앱이 실행되지 않는 이유를 이해하는데 시간을 할애하고 싶어 하지 않습니다. Xcode는 해당 작업을 빌드 시스템에 위임하고 어떤 경우에는 오류를 실행 가능하도록 변환하는데 매우 형편 없습니다. Have you ever got a _“framework X not found”_ error and you didn’t know what to do? 해당 버그에 대해 가능한 근본 원인을 받았다고 상상해 보시기 바랍니다.

## 개발자의 경험에서 시작 {#start-from-the-developers-experience}

Xcode의 혁신이 부족하거나 다른 프로그래밍 환경보다 많지 않은 이유 중 하나는 **기존 해결책에서 문제 분석을 시작하기** 때문입니다. 그 결과로 오늘날 찾은 대부분의 해결책은 동일한 아이디어와 작업흐름을 중심으로 돌아갑니다. 기존 해결책을 포함하는 것은 좋지만, 이것이 우리의 창의성을 제한하면 안됩니다.

We like to think as [Tom Preston](https://tom.preston-werner.com/) puts it in [this podcast](https://tom.preston-werner.com/): _“Most things can be achieved, whatever you have in your head you can probably pull off with code as long as is possible within the constrains of the universe”._ If **we imagine how we’d like the developer experience to be**, it’s just a matter of time to pull it off — by starting to analyze the problems from the developer experience gives us a unique point of view that will lead us to solutions that users will love to use.

모든 사람이 계속해서 불평을 가지는 불편함이더라도 우리는 모두가 하는 것을 따르고 싶은 유혹을 느낄 수 있습니다. 그러면 안됩니다. 앱을 아카이브 한다고 상상해 보시기 바랍니다. 어떻게 해야 할까요? 코드 서명은 어떻게 하면 좋을까요? Tuist로 어떤 프로세스를 간소화 할 수 있을까요? For example, adding support for [Fastlane](https://fastlane.tools/) is a solution to a problem that we need to understand first. We can get to the root of the problem by asking “why” questions. Once we narrow down where the motivation comes from, we can think of how Tuist can help them best. Maybe the solution is integrating with Fastlane, but it’s important we don’t disregard other equally valid solutions that we can put on the table before making trade-offs.

## Errors can and will happen {#errors-can-and-will-happen}

We, developers, have an inherent temptation to disregard that errors can happen. As a result, we design and test software only considering the ideal scenario.

Swift, its type system, and a well-architected code might help prevent some errors, but not all of them because some are out of our control. We can’t assume the user will always have an internet connection, or that the system commands will return successfully. The environments in which Tuist runs are not sandboxes that we control, and hence we need to make an effort to understand how they might change and impact Tuist.

Poorly handled errors result in bad user experience, and users might lose trust in the project. We want users to enjoy every single piece of Tuist, even the way we present errors to them.

We should put ourselves in the shoes of users and imagine what we’d expect the error to tell us. If the programming language is the communication channel through which errors propagate, and the users are the destination of the errors, they should be written in the same language that the target (users) speak. They should include enough information to know what happened and hide the information that is not relevant. Also, they should be actionable by telling users what steps they can take to recover from them.

And last but not least, our test cases should contemplate failing scenarios. Not only they ensure that we are handling errors as we are supposed to, but prevent future developers from breaking that logic.
