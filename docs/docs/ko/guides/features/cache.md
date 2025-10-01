---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---
# 캐시 {#cache}

> [!중요] 요구 사항
> - 1} 생성된 프로젝트</LocalizedLink>
> - 1}Tuist 계정 및 프로젝트</LocalizedLink>

Xcode의 빌드 시스템은 [증분 빌드](https://en.wikipedia.org/wiki/Incremental_build_model)를
제공하여 일반적인 상황에서 효율성을 향상시킵니다. 그러나 이 기능은 증분 빌드에 필수적인 데이터가 여러 빌드 간에 공유되지 않는 [지속적
통합(CI) 환경](https://en.wikipedia.org/wiki/Continuous_integration)에서는 부족합니다. 또한
**개발자는 복잡한 컴파일 문제를 해결하기 위해 로컬에서 이 데이터를 재설정하는 경우가 많기 때문에** 클린 빌드가 더 자주 발생합니다. 이로
인해 팀은 로컬 빌드가 완료되거나 지속적 통합 파이프라인이 풀 리퀘스트에 대한 피드백을 제공할 때까지 기다리는 데 과도한 시간을 소비하게
됩니다. 게다가 이러한 환경에서는 컨텍스트 전환이 빈번하게 일어나기 때문에 비생산성이 더욱 높아집니다.

Tuist는 캐싱 기능으로 이러한 문제를 효과적으로 해결합니다. 이 도구는 컴파일된 바이너리를 캐싱하여 빌드 프로세스를 최적화함으로써 로컬 개발
환경과 CI 환경 모두에서 빌드 시간을 크게 단축합니다. 이 접근 방식은 피드백 루프를 가속화할 뿐만 아니라 컨텍스트 전환의 필요성을 최소화하여
궁극적으로 생산성을 향상시킵니다.

## 온난화 {#온난화}

Tuist는 종속성 그래프에서 각 대상에 대해 해시</LocalizedLink>를 효율적으로
<LocalizedLink href="/guides/features/projects/hashing">활용하여 변경 사항을 감지합니다. 이
데이터를 활용하여 이러한 타깃에서 파생된 바이너리에 고유 식별자를 생성하고 할당합니다. 그런 다음 그래프를 생성할 때 Tuist는 원본 대상을
해당 바이너리 버전으로 원활하게 대체합니다.

*"워밍업"(* )으로 알려진 이 작업은 로컬에서 사용하거나 Tuist를 통해 팀원 및 CI 환경과 공유할 수 있는 바이너리를 생성합니다.
캐시를 워밍업하는 과정은 간단하며 간단한 명령으로 시작할 수 있습니다:


```bash
tuist cache
```

이 명령은 바이너리를 재사용하여 프로세스 속도를 높입니다.

## 사용량 {#사용량}

기본적으로 Tuist 명령은 프로젝트 생성이 필요한 경우 종속 요소를 캐시에서 사용할 수 있는 경우 해당 바이너리로 자동 대체합니다. 또한
집중할 대상 목록을 지정하는 경우, 사용 가능한 경우 종속 대상도 캐시된 바이너리로 대체합니다. 다른 방식을 선호하는 경우 특정 플래그를
사용하여 이 동작을 완전히 선택 해제할 수 있는 옵션이 있습니다:

::: 코드 그룹
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

> [!경고] 바이너리 캐싱은 시뮬레이터 또는 기기에서 앱을 실행하거나 테스트를 실행하는 등의 개발 워크플로우를 위해 설계된 기능입니다. 릴리스
> 빌드용이 아닙니다. 앱을 아카이브할 때는 `--no-binary-cache` 플래그를 사용하여 소스가 포함된 프로젝트를 생성하세요.

## 지원되는 제품 {#지원되는 제품}

다음 대상 제품만 Tuist에서 캐시할 수 있습니다:

- XCTest](https://developer.apple.com/documentation/xctest)에 의존하지 않는 프레임워크(정적 및
  동적)
- 번들
- 스위프트 매크로

XCTest에 의존하는 라이브러리 및 대상을 지원하기 위해 노력하고 있습니다.

> [참고] 업스트림 의존성 타깃이 캐싱할 수 없는 경우 업스트림 타깃도 캐싱할 수 없게 됩니다. 예를 들어 종속성 그래프 `A &gt; B`
> 에서 A가 B에 종속되어 있는 경우, B가 캐싱할 수 없는 경우 A도 캐싱할 수 없습니다.

## 효율성 {#효율성}

바이너리 캐싱으로 달성할 수 있는 효율성은 그래프 구조에 따라 크게 달라집니다. 최상의 결과를 얻으려면 다음을 권장합니다:

1. 종속성 그래프가 너무 중첩되는 것은 피하세요. 그래프는 얕을수록 좋습니다.
2. 구현 대상 대신 프로토콜/인터페이스 대상으로 종속성을 정의하고, 최상위 대상에서 구현을 종속성 주입하세요.
3. 자주 수정하는 타겟은 변경 가능성이 낮은 작은 타겟으로 분할하세요.

위의 제안은 <LocalizedLink href="/guides/features/projects/tma-architecture">모듈식
아키텍처</LocalizedLink>의 일부로, 바이너리 캐싱뿐만 아니라 Xcode의 기능을 최대한 활용할 수 있도록 프로젝트를 구성하는
방법으로 제안합니다.

## 권장 설정 {#recommended-setup}

메인 브랜치** 의 모든 커밋에서 **을 실행하여 캐시를 워밍업하는 CI 작업을 수행하는 것이 좋습니다. 이렇게 하면 캐시에 항상 `메인` 의
변경 사항에 대한 바이너리가 포함되므로 로컬 및 CI 브랜치가 이를 기반으로 점진적으로 빌드할 수 있습니다.

> [!팁] 캐시 워밍은 바이너리를 사용합니다 `tuist cache` 명령은 또한 바이너리 캐시를 사용하여 워밍 속도를 높입니다.

다음은 일반적인 워크플로우의 몇 가지 예입니다:

### 개발자가 새 기능에 대한 작업을 시작합니다 {#a-developer-starts-to-work-on-a-new-feature}.

1. `메인` 에서 새 지점을 만듭니다.
2. 그들은 `tuist generate` 을 운영합니다.
3. Tuist는 `메인` 에서 최신 바이너리를 가져와서 프로젝트를 생성합니다.

### 개발자가 업스트림에 변경 사항을 푸시합니다 {#a-developer-pushes-changes-upstream}.

1. CI 파이프라인은 `tuist build` 또는 `tuist test` 를 실행하여 프로젝트를 빌드하거나 테스트합니다.
2. 워크플로에서는 `메인` 에서 최신 바이너리를 가져와서 프로젝트를 생성합니다.
3. 그런 다음 프로젝트를 점진적으로 빌드하거나 테스트합니다.

## 문제 해결 {#문제 해결}

### 내 타겟에 바이너리를 사용하지 않습니다 {#it-doesnt-use-binaries-for-my-target}.

환경과 실행에 걸쳐 <LocalizedLink href="/guides/features/projects/hashing#debugging">해시가
결정론적</LocalizedLink>인지 확인하세요. 프로젝트에 절대 경로 등을 통해 환경에 대한 참조가 있는 경우 이런 문제가 발생할 수
있습니다. ` diff` 명령을 사용하여 `tuist generate` 또는 환경 또는 실행 간에 연속적으로 두 번 호출하여 생성된 프로젝트를
비교할 수 있습니다.

또한 대상이 <LocalizedLink href="/guides/features/cache#supported-products">캐시할 수 없는
대상</LocalizedLink>에 직접 또는 간접적으로 의존하지 않는지 확인하세요.
