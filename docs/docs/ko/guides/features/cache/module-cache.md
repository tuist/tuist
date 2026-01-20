---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---

# 모듈 캐시 {#module-cache}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/features/projects">생성된 프로젝트</LocalizedLink>
- <LocalizedLink href="/guides/server/accounts-and-projects">Tuist 계정 및 프로젝트</LocalizedLink>
<!-- -->
:::

모듈 캐시는 모듈을 바이너리(`.xcframework`s)로 캐시하고 여러 환경에서 공유하여 빌드 시간을 최적화할 수 있는 강력한 방법을
제공합니다. 이 기능을 사용하면 이전에 생성된 바이너리를 활용하여 반복 컴파일의 필요성을 줄이고 개발 프로세스의 속도를 높일 수 있습니다.

## 온난화 {#warming}

Tuist는 종속성 그래프에서 각 대상에 대해 <LocalizedLink href="/guides/features/projects/hashing">해시를 효율적으로 활용</LocalizedLink>하여 변경 사항을 감지합니다. 이
데이터를 활용하여 이러한 타깃에서 파생된 바이너리에 고유 식별자를 생성하고 할당합니다. 그런 다음 그래프를 생성할 때 Tuist는 원본 대상을
해당 바이너리 버전으로 원활하게 대체합니다.

*"워밍업"(* )으로 알려진 이 작업은 로컬에서 사용하거나 Tuist를 통해 팀원 및 CI 환경과 공유할 수 있는 바이너리를 생성합니다.
캐시를 워밍업하는 과정은 간단하며 간단한 명령으로 시작할 수 있습니다:


```bash
tuist cache
```

이 명령은 바이너리를 재사용하여 프로세스 속도를 높입니다.

## 사용량 {#usage}

기본적으로 Tuist 명령은 프로젝트 생성이 필요한 경우 종속 요소를 캐시에서 사용할 수 있는 경우 해당 바이너리로 자동 대체합니다. 또한
집중할 대상 목록을 지정하는 경우, 사용 가능한 경우 종속 대상도 캐시된 바이너리로 대체합니다. 다른 접근 방식을 선호하는 경우 특정 플래그를
사용하여 이 동작을 완전히 선택 해제할 수 있는 옵션이 있습니다:

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
<!-- -->
:::

::: warning
<!-- -->
바이너리 캐싱은 시뮬레이터나 기기에서 앱을 실행하거나 테스트를 실행하는 등의 개발 워크플로우를 위해 설계된 기능입니다. 릴리스 빌드용이
아닙니다. 앱을 아카이브할 때 `--no-binary-cache` 플래그를 사용하여 소스가 포함된 프로젝트를 생성하세요.
<!-- -->
:::

## 캐시 프로필 {#cache-profiles}

Tuist는 캐시 프로필을 지원하여 프로젝트 생성 시 타깃을 캐시된 바이너리로 얼마나 적극적으로 대체할지 제어할 수 있습니다.

- 빌트인:
  - `only-external`: 외부 종속성만 대체(시스템 기본값)
  - `모두 가능`: 가능한 한 많은 대상(내부 대상 포함)을 교체합니다.
  - `없음`: 캐시된 바이너리로 대체하지 않습니다.

`tuist 생성` 에서 `--cache-profile` 을 사용하여 프로필을 선택합니다:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely (backwards compatible)
tuist generate --no-binary-cache  # equivalent to --cache-profile none
```

효과적인 동작을 해결할 때의 우선 순위(가장 높은 것부터 가장 낮은 것까지):

1. `--바이너리 캐시 없음` → 프로필 `없음`
2. 타겟 포커스( `에 타겟 전달` 생성 ) → 프로필 `모두 가능`
3. `--캐시-프로필 &lt;값&gt;`
4. 구성 기본값(설정된 경우)
5. 시스템 기본값 (`전용-외부`)

## 지원되는 제품 {#supported-products}

다음 대상 제품만 Tuist에서 캐시할 수 있습니다:

- XCTest](https://developer.apple.com/documentation/xctest)에 의존하지 않는 프레임워크(정적 및
  동적)
- 번들
- 스위프트 매크로

XCTest에 의존하는 라이브러리 및 대상을 지원하기 위해 노력하고 있습니다.

::: info UPSTREAM DEPENDENCIES
<!-- -->
타깃이 캐싱할 수 없는 경우 업스트림 타깃도 캐싱할 수 없게 됩니다. 예를 들어, 종속성 그래프 `A &gt; B` 에서 A가 B에 종속되어
있는 경우, B가 캐싱할 수 없는 경우 A도 캐싱할 수 없게 됩니다.
<!-- -->
:::

## 효율성 {#efficiency}

바이너리 캐싱으로 달성할 수 있는 효율성은 그래프 구조에 따라 크게 달라집니다. 최상의 결과를 얻으려면 다음을 권장합니다:

1. 종속성 그래프가 너무 중첩되는 것은 피하세요. 그래프는 얕을수록 좋습니다.
2. 구현 대상 대신 프로토콜/인터페이스 대상으로 종속성을 정의하고, 최상위 대상에서 구현을 종속성 주입하세요.
3. 자주 수정하는 타깃은 변경 가능성이 낮은 작은 타깃으로 분할하세요.

위의 제안은 <LocalizedLink href="/guides/features/projects/tma-architecture">모듈식 아키텍처</LocalizedLink>의 일부로, 바이너리 캐싱뿐만 아니라 Xcode의 기능을 최대한 활용할 수 있도록 프로젝트를 구성하는
방법으로 제안합니다.

## 권장 설정 {#recommended-setup}

메인 브랜치** 의 모든 커밋에서 **을 실행하여 캐시를 워밍업하는 CI 작업을 수행하는 것이 좋습니다. 이렇게 하면 캐시에 항상 `메인` 의
변경 사항에 대한 바이너리가 포함되므로 로컬 및 CI 브랜치가 이를 기반으로 점진적으로 빌드할 수 있습니다.

::: tip CACHE WARMING USES BINARIES
<!-- -->
`tuist cache` 명령은 바이너리 캐시를 사용하여 온난화 속도를 높입니다.
<!-- -->
:::

다음은 일반적인 워크플로우의 몇 가지 예입니다:

### 개발자가 새로운 기능에 대한 작업을 시작합니다. {#a-developer-starts-to-work-on-a-new-feature}

1. `메인` 에서 새 지점을 만듭니다.
2. 그들은 `tuist generate` 을 운영합니다.
3. Tuist는 `메인` 에서 최신 바이너리를 가져와서 프로젝트를 생성합니다.

### 개발자가 변경 사항을 업스트림으로 푸시하는 경우 {#a-developer-pushes-changes-upstream}

1. CI 파이프라인은 `xcodebuild build` 또는 `tuist test` 를 실행하여 프로젝트를 빌드하거나 테스트합니다.
2. 워크플로에서는 `메인` 에서 최신 바이너리를 가져와서 프로젝트를 생성합니다.
3. 그런 다음 프로젝트를 점진적으로 빌드하거나 테스트합니다.

## 구성 {#configuration}

### 캐시 동시성 제한 {#cache-concurrency-limit}

기본적으로 튜이스트는 동시성 제한 없이 캐시 아티팩트를 다운로드 및 업로드하여 처리량을 최대화합니다. `
TUIST_CACHE_CONCURRENCY_LIMIT` 환경 변수를 사용하여 이 동작을 제어할 수 있습니다:

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

이는 네트워크 대역폭이 제한된 환경이나 캐시 작업 중 시스템 부하를 줄이는 데 유용할 수 있습니다.

## 문제 해결 {#troubleshooting}

### 내 타겟에 바이너리를 사용하지 않습니다. {#it-doesnt-use-binaries-for-my-targets}

환경과 실행에 걸쳐 <LocalizedLink href="/guides/features/projects/hashing#debugging">해시가 결정론적</LocalizedLink>인지 확인합니다. 프로젝트에 절대 경로 등을 통해 환경에 대한 참조가 있는 경우 이런 문제가 발생할 수
있습니다. ` diff` 명령을 사용하여 `tuist generate` 또는 환경 또는 실행 간에 연속적으로 두 번 호출하여 생성된 프로젝트를
비교할 수 있습니다.

또한 대상이
<LocalizedLink href="/guides/features/cache/generated-project#supported-products">캐시할 수 없는 대상</LocalizedLink>에 직접 또는 간접적으로 의존하지 않는지 확인하세요.

### 누락된 기호 {#missing-symbols}

소스를 사용할 때 Xcode의 빌드 시스템은 파생된 데이터를 통해 명시적으로 선언되지 않은 종속성을 해결할 수 있습니다. 그러나 바이너리 캐시에
의존하는 경우 종속성을 명시적으로 선언해야 하며, 그렇지 않으면 심볼을 찾을 수 없을 때 컴파일 오류가 발생할 수 있습니다. 이를 디버깅하려면
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect implicit-imports`</LocalizedLink> 명령을 사용하고 CI에서 설정하여 암시적 연결의 회귀를 방지하는 것이
좋습니다.
