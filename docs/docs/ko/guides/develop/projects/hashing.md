---
title: Hashing
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: 바이너리 캐싱과 선택적 테스트 기능의 기반이 되는 Tuist의 해싱 로직에 대해 배워봅니다.
---

# Hashing {#hashing}

<LocalizedLink href="/guides/develop/build/cache">캐싱</LocalizedLink>이나 선택적 테스트 수행과 같은 기능은 타겟이 변경되었는지 확인하는 방법이 필요합니다. Tuist는 타겟이 변경되었는지 확인하기 위해 의존성 그래프에서 각 타겟의 해시를 계산합니다. 해시는 다음의 속성을 기반으로 계산됩니다:

- 타겟의 속성 (예: 이름, 플랫폼, 결과물 등)
- 타겟의 파일
- 타겟 의존성의 해시

### 캐시 속성 {#cache-attributes}

추가로 캐싱에 대한 해시를 계산할 때, 다음 속성도 해시합니다.

#### Swift 버전 {#swift-version}

`/usr/bin/xcrun swift --version` 명령어를 수행하여 얻은 Swift 버전을 해시하여, 타겟과 바이너리 간의 Swift 버전 불일치로 인한 컴파일 오류를 방지합니다.

> [!NOTE] 모듈 안정성
> 이전 버전의 바이너리 캐싱은 `BUILD_LIBRARY_FOR_DISTRIBUTION` 빌드 설정에 의존하여 [모듈 안정성](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)을 활성화하고 모든 컴파일러 버전에서 바이너리를 사용할 수 있도록 합니다. 하지만 모듈 안정성을 지원하지 않는 타겟을 가지는 프로젝트에서 컴파일 문제가 발생합니다. 생성된 바이너리는 컴파일에 사용한 Swift 버전에 바인딩되고 Swift 버전은 프로젝트를 컴파일하는 버전과 일치해야 합니다.

#### 구성 {#configuration}

`-configuration` 플래그는 디버그 바이너리가 릴리즈 빌드에서 사용되지 않게 하고 릴리즈 바이너리가 디버그 빌드에서 사용되지 않게 하는 것입니다. 하지만 여전히 프로젝트에서 다른 구성을 제거하여 사용되지 않게 하는 메커니즘은 부족합니다.

## 디버깅 {#debugging}

환경이나 호출 간에 캐싱을 사용할 때 의도치 않은 동작이 발생한다면, 이것은 환경 간의 차이나 해싱 로직의 버그와 관련이 있을 수 있습니다. 문제를 디버그 하기 위해 다음의 동작을 권장합니다:

1. 모든 환경에서 동일한 [구성](#configuration) 과 [Swift 버전](#swift-version) 이 사용되었는지 확인합니다.
2. 두 번 연속으로 `tuist generate`를 호출하여 생성된 Xcode 프로젝트 간의 차이점이나 환경 간의 차이점을 확인합니다. 프로젝트를 비교하기 위해 `diff` 명령어를 사용할 수 있습니다. 생성된 프로젝트에는 해싱 로직이 의도치 않은 동작을 야기시키는 **절대 경로**가 포함될 수 있습니다.

> [!NOTE] 디버깅 경험 개선 계획
> 디버깅 경험 개선은 로드맵에 포함되어 있습니다. 차이를 이해하기 어려운 print-hashes 명령어는 해시 간의 차이점을 트리 구조로 보여주는 사용자 친화적인 명령어로 대체될 예정입니다.
