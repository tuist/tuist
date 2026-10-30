---
{
  "title": "해싱",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 해싱이 바이너리 캐싱과 선택적 테스팅을 어떻게 지원하는지 설명합니다."
}
---
# 해싱 {#hashing}

<.localized_link href="/guides/features/cache">캐싱</.localized_link>이나 선택적 테스팅 실행과 같은 기능은 대상이 변경되었는지 확인하는 방법이 필요합니다. Tuist는 의존성 그래프의 각 대상에 대해 해시를 계산하여 대상이 변경되었는지 판단합니다. 해시는 다음 속성을 기반으로 계산됩니다:

- 대상 속성(예: 이름, 플랫폼, 제품 등)
- 대상 파일
- 대상 의존성의 해시

### 캐시 속성 {#cache-attributes}

또한 <.localized_link href="/guides/features/cache">캐싱</.localized_link>을 위한 해시를 계산할 때 다음 속성도 함께 해시화합니다.

#### Swift 버전 {#swift-version}

대상과 바이너리 간 Swift 버전 불일치로 인한 컴파일 오류를 방지하기 위해 `/usr/bin/xcrun swift --version` 명령어를 실행하여 얻은 Swift 버전을 해시화합니다.

> [!NOTE]
> **모듈 안정성**
>
> 이전 버전의 바이너리 캐싱은 `BUILD_LIBRARY_FOR_DISTRIBUTION` 빌드 설정을 사용하여 [모듈 안정성](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)을 활성화하고 모든 컴파일러 버전에서 바이너리를 사용할 수 있도록 했습니다. 그러나 모듈 안정성을 지원하지 않는 대상이 포함된 프로젝트에서는 컴파일 문제가 발생했습니다. 생성된 바이너리는 컴파일 시 사용된 Swift 버전에 종속되며, 프로젝트를 컴파일할 때 사용한 Swift 버전과 일치해야 합니다.


#### 구성 {#configuration}

캐시 해시를 계산할 때 Tuist는 각 프로젝트와 대상의 설정을 해결된 빌드 구성으로 범위를 제한합니다. 이는 `--configuration`로 지정된 구성이며, 그렇지 않으면 프로젝트의 `defaultConfiguration`, 아니면 첫 번째 디버그 구성입니다. Tuist는 해당 구성의 이름, 변형, 빌드 설정 및 구성 파일 내용을 적용되는 공유 기본 설정과 함께 해시화합니다. 다른 구성을 추가, 제거 또는 변경해도 해결된 구성의 캐시 해시에는 영향을 주지 않습니다. 해결된 구성만 중요하므로 명시적 `--configuration`으로 채워진 캐시는 플래그 없이 동일한 구성으로 해결되는 명령어에서 읽을 수 있습니다.

## 디버깅 {#debugging}

환경이나 호출 간에 캐싱을 사용할 때 비결정적 동작이 관찰되면 환경 간 차이 또는 해싱 로직의 버그 때문일 수 있습니다. 문제를 디버깅하기 위해 다음 단계를 따르는 것을 권장합니다:

1. `tuist hash cache` 또는 `tuist hash selective-testing`를 실행합니다(<.localized_link href="/guides/features/cache">바이너리 캐싱</.localized_link> 또는 <.localized_link href="/guides/features/selective-testing">선택적 테스팅</.localized_link>용 해시). 해시를 복사하고 프로젝트 디렉터리 이름을 변경한 후 명령어를 다시 실행합니다. 해시가 일치해야 합니다.
2. 해시가 일치하지 않으면 생성된 프로젝트가 환경에 종속되어 있을 가능성이 높습니다. 두 경우 모두 `tuist graph --format json`를 실행하고 그래프를 비교하세요. 또는 프로젝트를 생성하고 [Diffchecker](https://www.diffchecker.com)와 같은 diff 도구로 `project.pbxproj` 파일을 비교하세요.
3. 해시는 동일하지만 환경(예: CI와 로컬) 간에 차이가 있다면 모든 곳에서 동일한 [구성](#configuration)과 [Swift 버전](#swift-version)을 사용하고 있는지 확인하세요. Swift 버전은 Xcode 버전에 종속되므로 Xcode 버전이 일치하는지 확인하세요.

해시가 여전히 비결정적이라면 알려주세요. 디버깅을 도와드리겠습니다.


> [!NOTE]
> **향상된 디버깅 경험 계획**
>
> 디버깅 경험을 개선하는 것이 로드맵에 포함되어 있습니다. 차이를 이해할 컨텍스트가 부족한 print-hashes 명령어는 트리 구조를 사용하여 해시 간 차이를 보여주는 더 사용자 친화적인 명령어로 대체될 예정입니다.
