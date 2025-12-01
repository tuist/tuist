---
{
  "title": "Projects",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn about Tuist's DSL for defining Xcode projects."
}
---
# Generated 프로젝트 {#generated-projects}

Generated는 복잡성과 비용을 적정 수준으로 유지하면서 이러한 문제를 극복할 수 있도록 도와줍니다. 이 방식은 Xcode 프로젝트를
기본적인 요소로 간주하며 추후 Xcode 업데이트에도 대응할 수 있으며, Xcode 프로젝트 생성을 활용해 팀이 모듈화 중심의 선언적 API를
사용할 수 있게 합니다. Tuist는 이러한 프로젝트 선언을 통해 모듈화의 복잡성을 단순화하고, 다양한 환경에서 빌드나 테스트 같은 워크플로를
최적화하고, Xcode 프로젝트를 발전시키고 누구나 쉽게 참여할 수 있게 합니다.

## 어떻게 동작할까? {#how-does-it-work}

Generated 프로젝트를 시작하려면, **Tuist의 Domain Specific Language(DSL)**를 사용해 프로젝트를 정의하면
됩니다. 이것은 `Workspace.swift`나 `Project.swift` 같은 매니페스트 파일을 사용합니다. 이전에 Swift
Package Manager를 사용해본 적이 있다면 이 방식과 유사합니다.

프로젝트를 정의하면 Tuist는 이를 관리하고 다룰 수 있는 다양한 워크플로를 제공합니다:

- **Generate:** 이것은 기본적인 워크플로입니다. Xcode와 호환되는 Xcode 프로젝트를 생성할 때 사용합니다.
- **<LocalizedLink href="/guides/features/build">Build</LocalizedLink>:** 이
  워크플로는 Xcode 프로젝트를 생성할 뿐만 아니라 `xcodebuild`를 통해 컴파일도 진행합니다.
- **<LocalizedLink href="/guides/features/test">Test</LocalizedLink>:** 빌드 워크플로와
  유사하게 동작하고, Xcode 프로젝트를 생성할 뿐만 아니라 `xcodebuild`를 통해 테스트도 수행합니다.

## Xcode 프로젝트의 과제 {#challenges-with-xcode-projects}

Xcode 프로젝트가 커질수록 불안정한 증분 빌드, 문제 발생 시 개발자가 자주 Xcode의 전역 캐시를 삭제하는 관행, 취약한 프로젝트 설정
등으로 인해 ** 생산성 저하에 직면할 수 있습니다**. 빠른 기능 개발을 유지하기 위해 일반적으로 다양한 전략을 모색합니다.

일부 조직은 [React Native](https://reactnative.dev/)와 같은 JavaScript 기반의 동적 런타임을 사용해
플랫폼을 추상화하여 컴파일러를 우회하기도 합니다. 이러한 접근 방식은 효과적일 수 있지만, [플랫폼의 네이티브 기능에 접근하기가
복잡해집니다](https://shopify.engineering/building-app-clip-react-native). 다른 조직은 명확한
경계를 확립할 수 있게 **코드베이스를 모듈화**하는 방식을 채택하여 코드베이스를 더 쉽게 다룰 수 있고 빌드 시간의 신뢰성을 향상시킵니다.
그러나 Xcode 프로젝트 형식은 모듈화를 염두에 두고 설계되지 않았으므로 일부만 이해하는 암묵적 구성과 빈번하게 충돌이 발생합니다. 이것으로
인해 버스 팩터(Bus Factor)가 낮아지고, 증분 빌드가 개선되더라도 빌드 실패 시 개발자가 여전히 Xcode의 빌드 캐시(예:
DerivedData)를 삭제하는 경우가 빈번하게 발생합니다. 이러한 문제를 해결하기 위해 어떤 조직은 **Xcode의 빌드 시스템을
포기**하고 [Buck](https://buck.build/)이나 [Bazel](https://bazel.build/) 같은 대안을 채택하기도
합니다. 그러나 이러한 방식은 [높은 복잡성과 유지 보수 부담](https://bazel.build/migrate/xcode)을 수반합니다.


## 대안 {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager(SPM)은 의존성 관리 중점이지만, Tuist는 다른 접근 방식을 제공합니다. Tuist를 사용하면
SPM 통합을 패키지 정의로만 사용하는 것이 아니라 프로젝트, 워크스페이스, 타겟, 스킴과 같은 익숙한 개념을 사용해 프로젝트의 구조를 설계할
수 있습니다.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)은 협업 환경에서 Xcode 프로젝트의 충돌을 줄이고
Xcode의 내부 구조의 복잡성을 단순화하기 위해 설계된 프로젝트 생성기입니다. 하지만 프로젝트는 [YAML](https://yaml.org/)
같은 직렬화 형식을 사용해 정의됩니다. Swift와 다르게 이것은 추가 도구를 사용하지 않으면 개발자가 추상화나 검증 로직을 확장할 수
없습니다. XcodeGen은 의존성을 내부 표현으로 매핑하고 검증 및 최적화할 수 있는 방법을 제공하지만 여전히 개발자가 Xcode의 세부사항을
직접 다뤄야 합니다. 이러한 이유로 XcodeGen은 Bazel 커뮤니티에서 볼 수 있듯이 [도구를
개발하는](https://github.com/MobileNativeFoundation/rules_xcodeproj) 것으로는 적합할 수 있지만
건강하고 생산적인 환경을 유지하면서 프로젝트를 포괄적으로 발전시키는 데에는 적합하지 않습니다.

### Bazel {#bazel}

[Bazel](https://bazel.build)은 원격 캐시 기능으로 유명한 고급 빌드 시스템으로 이러한 기능으로 Swift 커뮤니티에서
인기를 얻고 있습니다. 하지만 Xcode와 이 빌드 시스템의 확장성이 제한되어 있어 이것을 Bazel의 시스템으로 전환하는데 상당한 노력과 유지
보수가 필요합니다. Xcode와 Bazel을 통합하기 위해 막대한 투자를 할 수 있는 회사는 많지 않으며, 실제로 극히 일부 회사만 여기에
투자하고 있습니다. 흥미롭게도 커뮤니티에서는 Bazel의 XcodeGen을 활용해 Xcode 프로젝트를 생성하는
[도구](https://github.com/MobileNativeFoundation/rules_xcodeproj)를 만들었습니다. 그 결과
Bazel 파일에서 XcodeGen YAML을 거쳐 최종적으로 Xcode Project로 변환하는 복잡한 변환 체계가 형성되었습니다. 이러한
계층의 간접 구조는 문제 해결 과정을 복잡하게 만들어 문제를 진단하고 해결하는데 더 많은 어려움을 가져다 줍니다.
