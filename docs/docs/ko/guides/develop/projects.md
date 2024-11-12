---
title: Projects
titleTemplate: :title · Develop · Guides · Tuist
description: Xcode 프로젝트를 정의하는 Tuist의 DSL에 대해 배워봅니다.
---

# Projects {#projects}

Tuist Project는 복잡성과 비용을 적절하게 유지하면서 문제를 해결하는데 도움이 되는 해결책입니다. 이것은 Xcode 프로젝트를 기본 요소로 고려하여 Xcode 업데이트를 대응하고, Xcode 프로젝트 생성을 활용하여 팀에게 모듈화 중심의 선언적 API를 제공합니다. Tuist는 프로젝트 선언을 사용하여 모듈화\*\*의 복잡성을 단순화하고, 여러 환경에서의 빌드나 테스트와 같은 워크플로우를 최적화하고, Xcode 프로젝트의 발전과 관리에 대한 접근성을 넓힙니다.

## 어떻게 동작하나요? {#how-does-it-work}

Tuist Project를 시작하려면 \*\*Tuist's Domain Specific Language (DSL)\*\*를 사용하여 프로젝터를 정의하면 됩니다. 여기에서 `Workspace.swift` 또는 `Project.swift`와 같은 매니페스트 파일을 사용하여 프로젝트를 정의합니다. 이전에 Swift Package Manager를 사용해본 적이 있다면 그 접근 방식과 유사합니다.

프로젝트를 정의한 후, Tuist는 프로젝트를 관리하고 상호 작용할 수 있는 다양한 워크플로우를 제공합니다:

- **Generate:** 이것은 기본 워크플로우입니다. 이를 사용하면 Xcode와 호환되는 Xcode 프로젝트를 생성합니다.
- **<LocalizedLink href="/guides/develop/test">Build</LocalizedLink>:** 이 워크플로우는 Xcode 프로젝트를 생성할 뿐만 아니라 `xcodebuild`를 사용하여 프로젝트를 컴파일 합니다.
- **<0>Test</0>:** 빌드 워크플로우와 유사하게 동작하고, Xcode 프로젝트를 생성할 뿐만 아니라 `xcodebuild`를 활용하여 프로젝트를 테스트 합니다.

## Xcode 프로젝트의 문제 {#challenges-with-xcode-projects}

Xcode 프로젝트가 커짐에 따라 신뢰할 수 없는 증분 빌드, 개발자가 문제 해결을 위해 Xcode의 글로벌 캐시를 자주 지우는 것, 그리고 불안정한 프로젝트 구성과 같은 여러가지 이유로 **조직은 생산성 저하를 경험합니다**. 빠른 기능 개발을 유지하기 위해 조직은 일반적으로 다양한 전략을 검토합니다.

일부 조직은 [React Native](https://reactnative.dev/)와 같은 JavaScript 기반의 동적 런타임을 사용하여 플랫폼을 추상화해 컴파일러를 우회하는 방법을 선택합니다. 이런 접근 방식을 효율적일 수 있지만, [플랫폼의 네이티브 기능에 접근하는 것을 복잡하게 만듭니다](https://shopify.engineering/building-app-clip-react-native). 다른 조직은 명확한 경계를 설정해 코드베이스 작업을 더 쉽게 하고 빌드를 더 안정적으로 개선하는  **코드베이스 모듈화**를 선택합니다. 하지만 Xcode 프로젝트 형식은 모듈화를 염두에 두고 설계하지 않았으므로, 이해하기 어려운 암시적 구성과 잦은 충돌이 발생합니다. 이로 인해 프로젝트의 복잡성을 증가시켜 파악하기 어렵게 만들고, 증분 빌드가 향상될 수는 있지만 빌드 실패 시, Xcode의 빌드 캐시 (즉, Derived Data) 를 자주 지워야 할 수도 있습니다. 이런 문제를 해결하기 위해 일부 조직은 **Xcode 빌드 시스템을 포기**하고 대안으로 [Buck](https://buck.build/) 또는 [Bazel](https://bazel.build/)을 적용합니다. 하지만 이 방식은 [복잡성과 유지보수 부담](https://bazel.build/migrate/xcode)을 동반합니다.

## 대안 {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager (SPM) 이 의존성 관리에 집중하는 반면에 Tuist는 다른 접근 방식을 제공합니다. Tuist에서는 SPM 통합을 위한 패키지 정의 뿐만 아니라 프로젝트, 워크스페이스, 타겟, 그리고 스킴과 같은 익숙한 개념을 사용하여 프로젝트를 생성할 수 있습니다.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) is a dedicated project generator designed to reduce conflicts in collaborative Xcode projects and simplify some complexities of Xcode's internal workings. However, projects are defined using serializable formats like [YAML](https://yaml.org/). Unlike Swift, this doesn't allow developers to build upon abstractions or checks without incorporating additional tools. While XcodeGen does offer a way to map dependencies to an internal representation for validation and optimization, it still exposes developers to the nuances of Xcode. This might make XcodeGen a suitable foundation for [building tools](https://github.com/MobileNativeFoundation/rules_xcodeproj), as seen in the Bazel community, but it's not optimal for inclusive project evolution that aims to maintain a healthy and productive environment.

### Bazel {#bazel}

[Bazel](https://bazel.build) is an advanced build system renowned for its remote caching features, gaining popularity within the Swift community primarily for this capability. However, given the limited extensibility of Xcode and its build system, substituting it with Bazel's system demands significant effort and maintenance. Only a few companies with abundant resources can bear this overhead, as evident from the select list of firms investing heavily to integrate Bazel with Xcode. Interestingly, the community created a [tool](https://github.com/MobileNativeFoundation/rules_xcodeproj) that employs Bazel's XcodeGen to generate an Xcode project. This results in a convoluted chain of conversions: from Bazel files to XcodeGen YAML and finally to Xcode Projects. Such layered indirection often complicates troubleshooting, making issues more challenging to diagnose and resolve.
