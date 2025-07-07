---
title: Cache
titleTemplate: :title · Features · Guides · Tuist
description: 컴파일된 바이너리를 캐싱하고 다양한 환경 간에 공유하여 빌드 시간을 최적화 하세요.
---

# Cache {#cache}

> [!IMPORTANT] 요구사항
>
> - <LocalizedLink href="/guides/features/projects">생성된 프로젝트</LocalizedLink>
> - <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist 계정과 프로젝트</LocalizedLink>

Xcode의 빌드 시스템은 [증분 빌드](https://en.wikipedia.org/wiki/Incremental_build_model)를 제공하여 일반적인 상황에서 효율을 높입니다. 하지만 이 기능은 증분 빌드에 필요한 데이터가 서로 다른 빌드에서 공유되지 않으므로, [Continuous Integration (CI) 환경](https://en.wikipedia.org/wiki/Continuous_integration)에서는 적절하지 않습니다. 게다가 **개발자는 복잡한 컴파일 문제를 해결하기 위해 로컬에서 이 데이터를 초기화 하므로**, 클린 빌드가 자주 발생하게 됩니다. 팀은 이것으로 인해 로컬 빌드가 완료되거나 Continuous Integration 파이프라인이 Pull Request에 대한 피드백을 제공할 때까지 과도한 시간을 기다려야 합니다. 더욱이 이러한 환경에서 빈번한 컨텍스트 전환은 생산성을 더욱 악화시킵니다.

Tuist는 캐싱 기능으로 이 문제를 효과적으로 해결합니다. 이 툴은 컴파일된 바이너리를 캐시 하여 빌드 과정을 최적화하고, 로컬 개발 환경과 CI 환경 모두에서 빌드 시간을 크게 단축 시킵니다. 이 접근 방식은 피드백 순환을 가속화할 뿐만 아니라 컨텍스트 전환을 최소화하여 생산성을 극대화합니다.

## 워밍 {#warming}

Tuist는 각 타겟에 대한 의존성 그래프 변화를 감지하기 위해 효율적으로 <LocalizedLink href="/guides/features/projects/hashing">해시를 활용합니다.</LocalizedLink> 이 데이터를 활용하여, Tuist는 타겟의 바이너리에 고유 식별자를 생성하고 할당합니다. 이 데이터를 활용하여, Tuist는 타겟의 바이너리에 고유 식별자를 생성하고 할당합니다. 그래프가 생성될 때, Tuist는 기존 타겟을 바이너리로 원할하게 대체합니다.

이런 작업을 \*"워밍"\*이라 하며, Tuist를 통해 로컬 사용이나 팀원과 CI 환경에서 공유할 수 있는 바이너리를 생성합니다. 캐시 워밍 과정은 간단하며 단순한 명령어로 시작할 수 있습니다:

```bash
tuist cache
```

이 명령어는 더 빠르게 진행하기 위해 바이너리를 재사용합니다.

## 사용 {#usage}

기본적으로 Tuist 명령어는 프로젝트를 생성할 때, 캐시에 바이너리가 있는 경우 자동으로 의존성을 해당 바이너리로 대체합니다. 추가적으로 특정 타겟을 지정하면 Tuist는 해당 타겟에 의존하는 타겟도 캐시된 바이너리가 있는 경우 대체합니다. 다른 접근 방식을 선호하면, 특정 플래그를 사용하여 해당 동작을 완전히 비활성화 할 수 있습니다:

::: code-group

```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all
```

```bash [Testing]
tuist test
```

:::

> [!WARNING]\
> 바이너리 캐싱은 시뮬레이터나 디바이스에서 앱을 실행하거나 테스트를 실행하는 등의 개발 워크플로우를 위해 설계된 기능입니다. 이것은 릴리즈 빌드를 위한 기능이 아닙니다. 앱을 아카이브 할 때는, `--no-binary-cache` 플래그를 사용하여 소스가 포함된 프로젝트를 생성해야 합니다.

## 지원하는 결과물 {#supported-products}

다음의 타겟 결과물만 Tuist에 의해 캐시될 수 있습니다:

- [XCTest](https://developer.apple.com/documentation/xctest)를 의존하지 않는 프레임워크 (정적 프레임워크와 동적 프레임워크)
- 번들
- Swift Macros

현재 XCTest를 의존하는 라이브러리와 타겟을 지원하도록 작업 중입니다.

> [!NOTE] 상위 의존성\
> 타겟이 캐시가 불가능하면 해당 타겟에 의존하는 타겟도 캐시가 불가능합니다. 예를 들어, A가 B를 의존하고 `A > B`라는 의존성 그래프라면, B가 캐시가 불가능하면 A도 캐시가 불가능합니다.

## 효율성 {#efficiency}

바이너리 캐싱으로 인해 달성할 수 있는 효율성 수준은 그래프 구조에 강하게 의존합니다. 가장 좋은 결과를 달성하기 위해 다음을 권장합니다:

1. 과도하게 중첩된 의존성 그래프를 피합니다. 그래프는 얕을 수록 더 좋습니다.
2. 프로토콜/인터페이스 타겟으로 의존성을 정의하고, 최상위 타겟에서 의존성 주입을 구현합니다.
3. 자주 수정되는 타겟은 변경 가능성이 적은 타겟으로 나눕니다.

위의 제안은 바이너리 캐싱의 이점 뿐만 아니라 Xcode의 기능을 최대한 활용할 수 있게 프로젝트를 구조화 하는 방식을 제시하는 [The Modular Architecture](https://docs.tuist.dev/ko/guides/features/projects/tma-architecture)의 일부분입니다.

## 권장 설정 {#recommended-setup}

우리는 캐시를 미리 준비하기 위해 **main 브랜치에 커밋이 될 때마다 수행하는** CI 작업을 가지는 것을 권장합니다. 이렇게 하면 캐시는 항상 `main` 브랜치의 변경사항에 대한 바이너리를 포함하므로 로컬 및 CI 브랜치에서 점진적으로 빌드할 수 있습니다.

> [!TIP] 캐시 워밍은 바이너리를 사용합니다\
> `tuist cache` 명령어는 캐시 워밍을 빠르게 하기 위해 바이너리 캐시를 사용합니다.

다음은 일반적인 워크플로우의 예제입니다:

### 개발자가 새로운 기능 작업을 시작 {#a-developer-starts-to-work-on-a-new-feature}

1. `main`에서 새로운 브랜치를 생성합니다.
2. `tuist generate`를 수행합니다.
3. Tuist는 `main`에서 최근 바이너리를 가져와 프로젝트를 생성합니다.

### 개발자가 변경사항을 푸시 {#a-developer-pushes-changes-upstream}

1. CI 파이프라인은 프로젝트 빌드나 프로젝트 테스트를 위해 `tuist build` 또는 `tuist test`를 수행합니다.
2. 이 워크플로우는 `main`에서 최근 바이너리를 가져와 프로젝트를 생성합니다.
3. 그런 다음에 프로젝트를 점진적으로 빌드나 테스트를 진행합니다.

## 문제 해결 {#troubleshooting}

### 내 타겟에 대해 바이너리를 사용하지 않음 {#it-doesnt-use-binaries-for-my-targets}

같은 환경과 프로젝트 실행에서 <LocalizedLink href="/guides/features/projects/hashing#debugging">해시는 항상 동일해야</LocalizedLink> 합니다. 예를 들어, 절대 경로를 사용하는 것과 같이 프로젝트가 환경에 대한 참조를 포함하고 있을 때 발생할 수 있습니다. `diff` 명령어를 사용하여 두 번의 `tuist generate`를 통해 생성된 프로젝트나 환경 또는 프로젝트 실행 차이를 비교할 수 있습니다.

또한 타겟이 직접적으로나 간접적으로 <LocalizedLink href="/guides/features/cache.html#supported-products">캐시가 불가능한 타겟</LocalizedLink>에 의존하지 않도록 확인해야 합니다.
