---
{
  "title": "Projects",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn about Tuist's DSL for defining Xcode projects."
}
---
# 생성된 프로젝트 {#generated-projects}

Generated는 복잡성과 비용을 적정 수준으로 유지하면서 이러한 문제를 극복하는 데 도움이 되는 실행 가능한 대안입니다. 이 솔루션은
Xcode 프로젝트를 기본 요소로 간주하여 향후 Xcode 업데이트에 대한 복원력을 보장하고 Xcode 프로젝트 생성을 활용하여 팀에 모듈화에
중점을 둔 선언적 API를 제공합니다. Tuist는 프로젝트 선언을 사용하여 모듈화의 복잡성을 단순화하고**, 다양한 환경에서 빌드 또는
테스트와 같은 워크플로를 최적화하며, Xcode 프로젝트의 진화를 촉진하고 민주화합니다.

## 어떻게 작동하나요? {#HOW-DES-IT- WORK}

생성된 프로젝트를 시작하려면 **Tuist의 도메인 특정 언어(DSL)** 를 사용하여 프로젝트를 정의하기만 하면 됩니다. 이를 위해서는
`Workspace.swift` 또는 `Project.swift` 와 같은 매니페스트 파일을 사용해야 합니다. 이전에 Swift 패키지 관리자로
작업한 적이 있다면 접근 방식이 매우 유사합니다.

프로젝트를 정의한 후에는 프로젝트를 관리하고 상호 작용할 수 있는 다양한 워크플로를 제공합니다:

- **생성:** 생성: 기본 워크플로입니다. Xcode와 호환되는 Xcode 프로젝트를 생성하는 데 사용합니다.
- **<LocalizedLink href="/guides/features/build">Build</LocalizedLink>:** 이
  워크플로에서는 Xcode 프로젝트를 생성할 뿐만 아니라 컴파일을 위해 `xcodebuild` 을 사용합니다.
- **<LocalizedLink href="/guides/features/test">Test</LocalizedLink>:** 빌드 워크플로와
  매우 유사하게 작동하며, Xcode 프로젝트를 생성할 뿐만 아니라 `xcodebuild` 를 사용하여 테스트합니다.

## Xcode 프로젝트 관련 문제 {#challenges-with-xcode-projects}

Xcode 프로젝트가 성장함에 따라 **조직은 불안정한 증분 빌드, 문제가 발생하는 개발자의 잦은 Xcode 글로벌 캐시 지우기, 취약한
프로젝트 구성 등 여러 가지 요인으로 인해 생산성(** )이 저하될 수 있습니다. 신속한 기능 개발을 유지하기 위해 조직은 일반적으로 다양한
전략을 모색합니다.

일부 조직에서는 [React Native](https://reactnative.dev/)와 같은 자바스크립트 기반 동적 런타임을 사용하여
플랫폼을 추상화함으로써 컴파일러를 우회하는 방법을 선택하기도 합니다. 이 접근 방식은 효과적일 수 있지만 [플랫폼의 기본 기능에 대한 액세스가
복잡해집니다](https://shopify.engineering/building-app-clip-react-native). 다른 조직에서는
코드베이스를 모듈화( **** )하여 명확한 경계를 설정하고 코드베이스를 작업하기 쉽게 만들고 빌드 시간의 안정성을 개선하는 방법을 선택하기도
합니다. 그러나 Xcode 프로젝트 형식은 모듈화를 위해 설계되지 않았기 때문에 암시적 구성이 거의 이해되지 않고 충돌이 빈번하게 발생합니다.
이는 나쁜 버스 팩터로 이어지며, 증분 빌드가 개선되더라도 빌드 실패 시 개발자는 여전히 Xcode의 빌드 캐시(즉, 파생 데이터)를 자주 지울
수 있습니다. 이 문제를 해결하기 위해 일부 조직에서는 **Xcode의 빌드 시스템** 을 버리고 [벅](https://buck.build/)
또는 [바젤](https://bazel.build/)과 같은 대안을 채택하기도 합니다. 그러나 여기에는 [높은 복잡성 및 유지 관리
부담](https://bazel.build/migrate/xcode)이 따릅니다.


## 대안 {#대안}

### Swift 패키지 관리자 {#swift-package-manager}

Swift 패키지 관리자(SPM)는 주로 종속성에 중점을 두지만, Tuist는 다른 접근 방식을 제공합니다. Tuist를 사용하면 SPM 통합을
위해 패키지를 정의하는 데 그치지 않고 프로젝트, 작업 공간, 대상 및 체계와 같은 친숙한 개념을 사용하여 프로젝트를 구체화할 수 있습니다.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)은 공동 작업 Xcode 프로젝트의 충돌을 줄이고
Xcode 내부 작업의 일부 복잡한 작업을 간소화하도록 설계된 전용 프로젝트 생성기입니다. 그러나 프로젝트는
[YAML](https://yaml.org/)와 같은 직렬화 가능한 형식을 사용하여 정의됩니다. Swift와 달리 개발자가 추가 도구를 통합하지
않고 추상화나 검사를 기반으로 빌드할 수 없습니다. XcodeGen은 유효성 검사 및 최적화를 위해 종속성을 내부 표현에 매핑하는 방법을
제공하지만, 개발자는 여전히 Xcode의 뉘앙스에 노출됩니다. 따라서 Bazel 커뮤니티에서 볼 수 있듯이 [빌드
도구](https://github.com/MobileNativeFoundation/rules_xcodeproj)에 적합한 기반이 될 수 있지만
건강하고 생산적인 환경을 유지하는 것을 목표로 하는 포괄적인 프로젝트 발전에는 적합하지 않습니다.

### 배젤 {#배젤}

[Bazel](https://bazel.build)은 원격 캐싱 기능으로 유명한 고급 빌드 시스템으로, 주로 이 기능으로 인해 Swift
커뮤니티에서 인기를 얻고 있습니다. 하지만 Xcode와 그 빌드 시스템의 확장성이 제한적이기 때문에 이를 Bazel의 시스템으로 대체하려면
상당한 노력과 유지 관리가 필요합니다. 풍부한 리소스를 보유한 소수의 기업만이 이러한 오버헤드를 감당할 수 있으며, 이는 Bazel과
Xcode를 통합하기 위해 막대한 투자를 하는 일부 기업 목록에서 알 수 있습니다. 흥미롭게도 커뮤니티에서는 Bazel의 XcodeGen을
사용하여 Xcode 프로젝트를 생성하는
[도구](https://github.com/MobileNativeFoundation/rules_xcodeproj)를 만들었습니다. 그 결과
Bazel 파일에서 XcodeGen YAML로, 그리고 마지막으로 Xcode 프로젝트로의 복잡한 변환 체인이 생성됩니다. 이러한 계층화된 간접
전달은 문제 해결을 복잡하게 만들어 문제를 진단하고 해결하기 어렵게 만드는 경우가 많습니다.
