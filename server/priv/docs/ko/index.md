---
{
  "title": "Tuist란 무엇인가요?",
  "description": "Tuist는 엔지니어링 팀과 코딩 에이전트를 위한 빌드 플랫폼입니다. Xcode, Gradle, Bazel, Elixir, Rust 전반의 빌드 및 테스트 워크플로를 지원합니다. Rust 지원은 현재 카나리 버전에서 제공됩니다. 기능은 툴체인에 따라 다르며, Rust 컴파일 캐싱은 실험 단계입니다."
}
---

# 팀과 코딩 에이전트를 위한 빌드 플랫폼

**Tuist는 엔지니어링 팀과 코딩 에이전트를 위한 빌드 플랫폼입니다.** Xcode, Gradle, Bazel, Elixir, Rust 전반의 빌드 및 테스트 워크플로를 지원합니다. Once 지원은 카나리 버전에서 제공됩니다. 기존에 사용하던 빌드 시스템을 대체하지 않고 그대로 활용할 수 있습니다. 제공되는 기능은 툴체인에 따라 다릅니다. Rust 프로젝트는 닥테스트, 불안정한 테스트 감지, 실험적 컴파일 캐싱을 포함한 Cargo 빌드 및 테스트 인사이트를 제공합니다. Once는 공유 캐싱, 빌드 및 테스트 인사이트, 샤딩, 지원되는 앱 미리보기를 위해 네이티브로 연결됩니다.

빌드 시스템에 맞는 <.localized_link href="/guides/get-started">시작하기 경로</.localized_link> 중 하나를 따르세요. Once는 Tuist CLI 없이 직접 연결되며, 다른 경로는 설치해야 할 Tuist 도구를 안내합니다.

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
    details="생성된 Xcode 프로젝트에서 변경 사항의 영향을 받는 테스트만 실행하여 피드백을 몇 초 안에 받습니다."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="러너"
    details="관리형 macOS 및 Linux 러너에서 CI를 실행하며, 개발자 머신이 사용하는 것과 동일한 캐시에 가까이 접근합니다."
    link="/guides/features/runners"
/>
  <.home_card
    title="미리보기"
    details="URL로 앱을 즉시 공유하세요. 스토어 심사 지연 없이, 복잡한 설정 없이 가능합니다."
    link="/guides/features/previews"
/>
  <.home_card
    title="생성된 프로젝트"
    details="Swift로 Xcode 프로젝트를 정의하고 일관되게 생성합니다. 병합 충돌을 제거하고 모듈 캐시를 활용합니다."
    link="/guides/features/projects"
/>
  <.home_card
    title="패키지 레지스트리"
    details="Tuist의 캐시 네트워크로 뒷받침되는 레지스트리를 통해 Swift 패키지를 몇 분이 아닌 몇 초 안에 해결합니다."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="번들 크기"
    details="앱을 가볍게 유지하도록 분석하여 사용자가 더 빠르게 다운로드받고 스토어 가이드라인을 충족합니다."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 대규모로 배포하는 팀들이 신뢰합니다

**[Trendyol](https://www.trendyol.com/), [Etsy](https://www.etsy.com/), [Bumble](https://bumble.com/), [Monzo](https://monzo.com/), [Bending Spoons](https://bendingspoons.com/) 및 100개 이상의 다른 기업들의 팀**이 iOS 및 Android 코드베이스 전반에서 Tuist를 통해 더 빠르게 배포합니다.
