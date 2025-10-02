---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# 해싱 {#해싱}

1}캐싱</LocalizedLink> 또는 선택적 테스트 실행과 같은 기능을 사용하려면 대상이 변경되었는지 확인할 수 있는 방법이 필요합니다.
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

> [참고] 모듈 안정성 이전 버전의 바이너리 캐싱은 `BUILD_LIBRARY_FOR_DISTRIBUTION` 빌드 설정에 의존하여 [모듈
> 안정성](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)을
> 활성화하고 모든 컴파일러 버전에서 바이너리를 사용할 수 있도록 했습니다. 그러나 모듈 안정성을 지원하지 않는 타깃을 사용하는 프로젝트에서
> 컴파일 문제가 발생했습니다. 생성된 바이너리는 컴파일에 사용된 Swift 버전에 바인딩되며, 이 Swift 버전은 프로젝트 컴파일에 사용된
> 버전과 일치해야 합니다.

#### 구성 {#configuration}

`-configuration` 플래그의 아이디어는 디버그 바이너리가 릴리스 빌드에서 사용되지 않도록 하고 그 반대의 경우도 마찬가지입니다.
그러나 프로젝트에서 다른 구성을 제거하여 사용하지 못하도록 하는 메커니즘은 아직 없습니다.

## 디버깅 중 {#디버깅}

여러 환경 또는 호출에서 캐싱을 사용할 때 비결정적 동작을 발견하는 경우 환경 간 차이 또는 해싱 로직의 버그와 관련이 있을 수 있습니다. 다음
단계에 따라 문제를 디버깅하는 것이 좋습니다:

1. 여러 환경에서 동일한 [구성](#configuration) 및 [Swift 버전](#swift-version)이 사용되는지 확인합니다.
2. `tuist generate` 을 두 번 연속으로 호출하여 생성된 Xcode 프로젝트 간에 차이가 있는지 또는 환경 간에 차이가 있는지
   확인합니다. ` diff` 명령을 사용하여 프로젝트를 비교할 수 있습니다. 생성된 프로젝트에 **절대 경로** 가 포함되어 있어 해싱
   로직이 비결정적일 수 있습니다.

> [!참고] 더 나은 디버깅 환경 계획 디버깅 환경 개선은 로드맵에 포함되어 있습니다. 차이점을 이해하기 위한 컨텍스트가 부족한
> print-hashes 명령은 트리와 같은 구조를 사용하여 해시 간의 차이를 표시하는 보다 사용자 친화적인 명령으로 대체될 예정입니다.
