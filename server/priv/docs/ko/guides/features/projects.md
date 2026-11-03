---
{
  "title": "프로젝트",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Swift로 Xcode 프로젝트를 정의하고 Tuist로 일관되게 생성하세요. 병합 충돌을 제거하고, 의존성을 그래프 형태로 모델링하며, 모듈 캐시를 활용하세요."
}
---
# 생성된 프로젝트 {#generated-projects}

Tuist Generated Projects는 복잡성과 비용을 허용 가능한 수준으로 유지하면서 이러한 문제를 극복하는 데 도움이 되는 실현 가능한 대안입니다. Xcode 프로젝트를 기본 요소로 간주하여 향후 Xcode 업데이트에 대한 탄력성을 보장하고, 모듈화에 중점을 둔 선언형 API를 팀에 제공하기 위해 Xcode 프로젝트 생성을 활용합니다. Tuist는 프로젝트 선언을 사용하여 모듈화의 복잡성을 단순화하고, 다양한 환경에서 빌드나 테스트와 같은 워크플로를 최적화하며, Xcode 프로젝트의 진화를 촉진하고 대중화합니다.

## 작동 방식은? {#how-does-it-work}

생성된 프로젝트를 시작하려면 **Tuist의 도메인 특화 언어(DSL)** 을 사용하여 프로젝트를 정의하기만 하면 됩니다. 여기에는 `Workspace.swift` 또는 `Project.swift`과 같은 매니페스트 파일을 사용하는 작업이 포함됩니다. 이전에 Swift Package Manager를 사용해 본 적이 있다면 접근 방식이 매우 유사합니다.

프로젝트를 정의하면 Tuist는 이를 관리하고 상호 작용하기 위한 다양한 워크플로를 제공합니다.

- **생성:** 이는 기본적인 워크플로입니다. 이를 사용하여 Xcode와 호환되는 Xcode 프로젝트를 만듭니다.
- **<.localized_link href="/cli/build">빌드</.localized_link>:** 이 워크플로는 Xcode 프로젝트를 생성할 뿐만 아니라 `xcodebuild`을 사용하여 컴파일합니다.
- **<.localized_link href="/cli/test">테스트</.localized_link>:** 빌드 워크플로와 매우 유사하게 작동하며, Xcode 프로젝트를 생성할 뿐만 아니라 `xcodebuild`을 사용하여 테스트합니다.

## Xcode 프로젝트의 과제 {#challenges-with-xcode-projects}

Xcode 프로젝트가 성장함에 따라 **조직은 생산성 저하에 직면할 수 있습니다**. 이는 신뢰할 수 없는 증분 빌드, 문제 발생 시 개발자가 Xcode의 전역 캐시를 자주 지우는 행위, 그리고 불안정한 프로젝트 구성 등 여러 요인에 기인합니다. 빠른 기능 개발을 유지하기 위해 조직은 일반적으로 다양한 전략을 모색합니다.

일부 조직은 [React Native](https://reactnative.dev/)와 같은 JavaScript 기반 동적 런타임을 사용하여 플랫폼을 추상화함으로써 컴파일러를 우회하기로 선택합니다. 이 접근 방식이 효과적일 수 있지만 [플랫폼의 네이티브 기능에 대한 액세스가 복잡해집니다](https://shopify.engineering/building-app-clip-react-native). 다른 조직은 **코드베이스를 모듈화**하는 옵션을 선택하는데, 이는 명확한 경계를 설정하여 코드베이스 작업을 용이하게 하고 빌드 시간의 신뢰성을 향상시킵니다. 그러나 Xcode 프로젝트 형식은 모듈화를 위해 설계되지 않았으며, 소수만 이해하는 암시적 구성과 빈번한 충돌을 초래합니다. 이로 인해 버스 팩터가 낮아지며, 증분 빌드가 개선될 수 있더라도 빌드가 실패할 때 개발자는 여전히 Xcode의 빌드 캐시(즉, 파생 데이터)를 자주 지울 수 있습니다. 이를 해결하기 위해 일부 조직은 **Xcode의 빌드 시스템을 포기**하고 [Buck](https://buck.build/)이나 [Bazel](https://bazel.build/)과 같은 대안을 채택하기로 선택합니다. 그러나 이는 [높은 복잡성과 유지 관리 부담](https://bazel.build/migrate/xcode)을 동반합니다.


## 대안 {#alternatives}

### Swift Package Manager {#swift-package-manager}

Swift Package Manager(SPM)가 주로 의존성에 중점을 두는 반면, Tuist는 다른 접근 방식을 제공합니다. Tuist를 사용하면 SPM 통합을 위한 패키지를 정의하는 것을 넘어, 프로젝트, 워크스페이스, 타겟 및 스킴과 같은 익숙한 개념을 사용하여 프로젝트를 구성합니다.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)은 협업 Xcode 프로젝트에서의 충돌을 줄이고 Xcode 내부 작동의 일부 복잡성을 단순화하도록 설계된 전용 프로젝트 생성기입니다. 그러나 프로젝트는 [YAML](https://yaml.org/)과 같은 직렬화 가능한 형식을 사용하여 정의됩니다. Swift와 달리 이는 추가 도구를 통합하지 않고서는 추상화나 검사를 기반으로 구축할 수 없습니다. XcodeGen은 검증 및 최적화를 위해 의존성을 내부 표현으로 매핑하는 방법을 제공하지만, 여전히 개발자를 Xcode의 미묘한 차이점에 노출시킵니다. 이는 Bazel 커뮤니티에서 볼 수 있듯이 [도구 구축](https://github.com/MobileNativeFoundation/rules_xcodeproj)을 위한 적합한 기반이 될 수 있지만, 건강하고 생산적인 환경을 유지하려는 포용적인 프로젝트 진화에는 최적이지 않습니다.

### Bazel {#bazel}

[Bazel](https://bazel.build)은 원격 캐싱 기능으로 유명한 고급 빌드 시스템으로, 주로 이 능력 때문에 Swift 커뮤니티 내에서 인기를 얻고 있습니다. 그러나 Xcode와 그 빌드 시스템의 제한된 확장성을 고려할 때, 이를 Bazel의 시스템으로 대체하려면 상당한 노력과 유지 관리가 필요합니다. 풍부한 자원을 가진 소수의 기업만이 이러한 오버헤드를 감당할 수 있으며, 이는 Bazel을 Xcode와 통합하기 위해 막대한 투자를 하는 소수 기업의 목록에서 알 수 있습니다. 흥미롭게도 커뮤니티는 Bazel의 XcodeGen을 사용하여 Xcode 프로젝트를 생성하는 [도구](https://github.com/MobileNativeFoundation/rules_xcodeproj)를 만들었습니다. 이는 Bazel 파일에서 XcodeGen YAML, 그리고 최종적으로 Xcode 프로젝트로 이어지는 복잡한 변환 체인을 초래합니다. 이러한 계층화된 간접성은 종종 문제 해결을 복잡하게 만들어 문제를 진단하고 해결하는 것을 더 어렵게 만듭니다.
