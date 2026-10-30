---
{
  "title": "Tuist란 무엇인가요?",
  "description": "개발자를 위한 가상 플랫폼 팀입니다. 각 툴체인에 맞춘 기능으로 Xcode, Gradle, Bazel, Elixir, Rust의 빌드 인프라를 구축하세요."
}
---

# 배포하는 개발자를 위한 가상 플랫폼 팀

**Tuist는 팀의 앱 개발을 확장하고 더 빠르게 배포할 수 있도록 도와줍니다**. 방대한 코드베이스의 복잡성을 팀의 성장에 맞춰 생산적인 경험으로 전환합니다. 이미 사용 중인 Xcode, Gradle, Bazel, Elixir 및 Rust 프로젝트의 빌드 시스템과 연동됩니다. 제공되는 기능은 툴체인에 따라 다릅니다. Rust 프로젝트는 doctest, 불안정한 테스트 감지 및 실험적 컴파일 캐싱을 포함한 Cargo 빌드 및 테스트 인사이트를 제공합니다.

먼저 <.localized_link href="/guides/install-tuist">Tuist 명령줄 인터페이스 설치</.localized_link>를 시작한 다음, 빌드 시스템에 맞는 <.localized_link href="/guides/get-started">시작하기 가이드</.localized_link> 중 하나를 따르세요.

<br/>

<.home_cards>
  <.home_card
    title="캐시"
    details="팀과 CI 간에 컴파일 출력을 공유하세요. Xcode의 컴파일 캐시, Tuist의 모듈 캐시, Gradle의 빌드 캐시, Bazel의 원격 캐시 및 Rust의 실험적 컴파일 캐시와 연동됩니다."
    supported_for="apple,gradle,bazel,rust"
    link="/guides/features/cache"
/>
  <.home_card
    title="빌드 및 테스트 인사이트"
    details="Xcode, Gradle, Bazel, Elixir 및 Rust 프로젝트 전반에서 빌드 및 테스트 소요 시간, 실패, 불안정성 및 회귀를 추적합니다."
    supported_for="apple,gradle,bazel,elixir,rust"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="선택적 테스팅"
    details="변경 사항의 영향을 받는 테스트만 Xcode 및 생성된 프로젝트에서 실행하여 몇 초 만에 피드백을 받으세요."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="러너"
    details="관리형 macOS 및 Linux 러너에서 CI를 실행하며, 개발자 머신이 사용하는 것과 동일한 캐시에 가까이 접근합니다."
    link="/guides/features/runners"
/>
  <.home_card
    title="프리뷰"
    details="URL로 앱을 즉시 공유하세요. 스토어 검토 지연이나 복잡한 설정이 필요 없습니다."
    link="/guides/features/previews"
/>
  <.home_card
    title="생성된 프로젝트"
    details="Swift로 Xcode 프로젝트를 정의하고 일관되게 생성하세요. 병합 충돌을 제거하고 모듈 캐시를 활용할 수 있습니다."
    link="/guides/features/projects"
/>
  <.home_card
    title="패키지 레지스트리"
    details="Tuist의 캐시 네트워크로 뒷받침되는 레지스트리를 통해 Swift 패키지를 몇 분이 아닌 몇 초 안에 해결하세요."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="번들 크기"
    details="앱을 경량화하여 사용자가 더 빠르게 다운로드할 수 있도록 하고 스토어 가이드라인을 충족하세요."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 대규모로 배포하는 팀들이 신뢰합니다

**[Trendyol](https://www.trendyol.com/), [Etsy](https://www.etsy.com/), [Bumble](https://bumble.com/), [Monzo](https://monzo.com/), [Bending Spoons](https://bendingspoons.com/) 및 100개 이상의 다른 회사들의 팀**이 iOS 및 Android 코드베이스에서 Tuist를 통해 더 빠르게 배포합니다.
