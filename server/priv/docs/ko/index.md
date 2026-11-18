---
{
  "title": "Tuist란 무엇인가요?",
  "description": "Tuist는 엔지니어링 팀과 코딩 에이전트를 위한 빌드 플랫폼입니다. Xcode, Gradle, Bazel, Elixir, Rust 전반의 빌드 및 테스트 워크플로를 지원합니다. Once 지원은 카나리 버전에서 제공됩니다. 기능은 툴체인에 따라 다르며, Rust 컴파일 캐싱은 실험적 기능입니다."
}
---

# 팀과 코딩 에이전트를 위한 빌드 플랫폼

**Tuist는 엔지니어링 팀과 코딩 에이전트를 위한 빌드 플랫폼입니다.** Xcode, Gradle, Bazel, Elixir, Rust의 빌드 및 테스트 워크플로를 지원합니다. Once 지원은 카나리 버전에서 제공됩니다. 기존에 사용하던 빌드 시스템을 대체하지 않고 그대로 활용할 수 있습니다. 사용 가능한 기능은 툴체인에 따라 다릅니다. Rust 프로젝트는 doctest, 불안정한 테스트 감지, 실험적 컴파일 캐싱을 포함한 Cargo 빌드 및 테스트 인사이트를 제공합니다. Once는 공유 캐싱, 빌드 및 테스트 인사이트, 샤딩, 지원되는 앱 미리보기를 위해 네이티브로 연결됩니다.

빌드 시스템에 맞는 <.localized_link href="/guides/get-started">시작하기 가이드</.localized_link> 중 하나를 따르세요. Once는 Tuist CLI 없이 직접 연결되며, 다른 경로는 설치해야 할 Tuist 도구를 안내합니다.

<br/>

<.home_cards>
  <.home_card
    title="캐시"
    details="팀과 CI 간에 빌드 산출물을 공유하세요. Xcode의 컴파일 캐시, Tuist의 모듈 캐시, Gradle의 빌드 캐시, Bazel의 원격 캐시, Elixir의 의존성 캐시, Rust의 실험적 컴파일 캐시, Once의 공유 액션 캐시와 연동됩니다."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="빌드 및 테스트 인사이트"
    details="Xcode, Gradle, Bazel, Elixir, Rust, Once 프로젝트 전반에서 빌드 및 테스트 소요 시간, 실패, 불안정성, 회귀를 추적합니다."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="선택적 테스팅"
    details="생성된 Xcode 프로젝트에서 변경되지 않은 테스트 타겟을 건너뛰며, 개별 XCTest/XCUITest 선택을 위한 얼리 액세스 커버리지 전략을 제공합니다."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="러너"
    details="관리형 macOS 및 Linux 러너에서 CI를 실행하며, 개발자 머신이 사용하는 것과 동일한 캐시에 가까이 위치합니다."
    link="/guides/features/runners"
/>
  <.home_card
    title="미리보기"
    details="지원되는 모바일 앱, macOS 앱, macOS/Linux 명령줄 도구를 URL을 통해 공유하세요. 빌드, 서명, 수신자 호환성 요구 사항이 적용됩니다."
    link="/guides/features/previews"
/>
  <.home_card
    title="생성된 프로젝트"
    details="Swift로 Xcode 프로젝트를 정의하고 일관되게 생성하세요. 프로젝트 파일 충돌을 줄이고 모듈 캐시를 활용합니다."
    link="/guides/features/projects"
/>
  <.home_card
    title="패키지 레지스트리"
    details="Git 리포지토리를 클론하는 대신 레지스트리 프로토콜을 통해 지원되는 Swift 패키지를 가져옵니다."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="번들 크기"
    details="시간 경과에 따른 지원되는 Apple 및 Android 번들 크기를 추적하고 크기 회귀를 조사합니다."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 대규모로 배포하는 팀들이 신뢰합니다

팀이 채택한 워크플로와 보고된 결과를 확인하려면 [고객 사례](https://tuist.dev/customers)를 읽어보세요.
