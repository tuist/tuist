---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# 해싱 {#hashing}

<LocalizedLink href="/guides/features/cache">캐싱</LocalizedLink> 또는 선택적 테스트 실행과 같은 기능을 사용하려면 대상이 변경되었는지 확인할 수 있는 방법이 필요합니다.
Tuist는 종속성 그래프에서 각 대상에 대한 해시를 계산하여 대상의 변경 여부를 확인합니다. 해시는 다음 속성을 기반으로 계산됩니다:

- 대상의 속성(예: 이름, 플랫폼, 제품 등)
- 대상의 파일
- 대상의 종속성 해시

### 캐시 속성 {#cache-attributes}

또한 <LocalizedLink href="/guides/features/cache">캐싱</LocalizedLink>에 대한 해시를 계산할 때
다음 속성도 해시합니다.

#### 스위프트 버전 {#swift-version}

대상과 바이너리 간의 Swift 버전 불일치로 인한 컴파일 오류를 방지하기 위해 `/usr/bin/xcrun swift --version`
명령을 실행하여 얻은 Swift 버전을 해시화합니다.

::: info MODULE STABILITY
<!-- -->
이전 버전의 바이너리 캐싱은 `BUILD_LIBRARY_FOR_DISTRIBUTION` 빌드 설정에 의존하여 [모듈
안정성](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)을
활성화하고 모든 컴파일러 버전에서 바이너리를 사용할 수 있도록 했습니다. 그러나 모듈 안정성을 지원하지 않는 타깃을 사용하는 프로젝트에서 컴파일
문제가 발생했습니다. 생성된 바이너리는 컴파일에 사용된 Swift 버전에 바인딩되며, 이 Swift 버전은 프로젝트 컴파일에 사용된 버전과
일치해야 합니다.
<!-- -->
:::

#### 구성 {#configuration}

`-configuration` 플래그의 아이디어는 디버그 바이너리가 릴리스 빌드에서 사용되지 않도록 하고 그 반대의 경우도 마찬가지입니다.
그러나 프로젝트에서 다른 구성을 제거하여 사용하지 못하도록 하는 메커니즘은 아직 없습니다.

## 디버깅 중 {#debugging}

여러 환경 또는 호출에서 캐싱을 사용할 때 비결정적 동작을 발견하는 경우 환경 간 차이 또는 해싱 로직의 버그와 관련이 있을 수 있습니다. 다음
단계에 따라 문제를 디버깅하는 것이 좋습니다:

1. `tuist 해시 캐시` 또는 `tuist 해시 선택적 테스트`
   (<LocalizedLink href="/guides/features/cache">바이너리 캐싱</LocalizedLink> 또는
   <LocalizedLink href="/guides/features/selective-testing">선택적 테스트</LocalizedLink>용 해시)를 실행하고 해시를 복사한 다음 프로젝트 디렉터리 이름을 바꾸고 명령을 다시 실행합니다. 해시가
   일치해야 합니다.
2. 해시가 일치하지 않는 경우 생성된 프로젝트가 환경에 따라 달라질 수 있습니다. 두 경우 모두 `tuist graph --format
   json` 을 실행하여 그래프를 비교하세요. 또는 프로젝트를 생성하고
   [Diffchecker](https://www.diffchecker.com)와 같은 diff 도구를 사용하여
   `project.pbxproj` 파일을 비교합니다.
3. 해시는 동일하지만 환경(예: CI 및 로컬)에 따라 다른 경우 모든 곳에서 동일한 [구성](#configuration) 및 [Swift
   버전](#swift-version)이 사용되는지 확인하세요. Swift 버전은 Xcode 버전에 연결되므로 Xcode 버전이 일치하는지
   확인하세요.

해시가 여전히 결정적이지 않은 경우 알려주시면 디버깅을 도와드리겠습니다.


::: info BETTER DEBUGGING EXPERIENCE PLANNED
<!-- -->
디버깅 환경을 개선하는 것은 저희의 로드맵에 포함되어 있습니다. 차이점을 이해하기 위한 컨텍스트가 부족한 print-hashes 명령은 트리와
같은 구조를 사용하여 해시 간의 차이점을 표시하는 보다 사용자 친화적인 명령으로 대체될 예정입니다.
<!-- -->
:::
