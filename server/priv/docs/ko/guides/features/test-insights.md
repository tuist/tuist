---
{
  "title": "테스트 인사이트",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 테스트 인사이트를 통해 Xcode, Gradle, Bazel, Elixir, Rust, Once 프로젝트에서 불안정하거나 느린 테스트를 식별하세요."
}
---
# 테스트 인사이트 {#test-insights}

느린 테스트 식별, 불안정한 테스트 추적, 실패한 CI 실행의 빠른 이해를 통해 테스트 스위트의 상태를 모니터링하려면 테스트 인사이트를 사용하세요. 현재 Xcode, Gradle, Bazel, Elixir, Rust 및 Once를 지원합니다. 제공되는 결과와 타이밍은 러너에 따라 다릅니다. 지원되는 빌드 시스템에서 테스트가 실행하는 코드를 확인하려면 <.localized_link href="/guides/features/test-code-coverage">코드 커버리지</.localized_link>를 참조하세요. [느린 테스트](https://tuist.dev/solutions/slow-tests)와 [불안정한 테스트](https://tuist.dev/solutions/flaky-tests)에 대한 안내는 솔루션 가이드를 참조하세요.

<.home_cards>
  <.home_card
    title="Xcode"
    details="스킴 포스트 액션과 Tuist CLI를 사용하여 Xcode 테스트 분석을 추적합니다."
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle 플러그인을 사용하여 Gradle 테스트 분석을 추적합니다."
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test를 통해 테스트를 실행하여 Bazel 테스트 분석을 추적합니다."
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Tuist Hex 패키지를 사용하여 Elixir 프로젝트의 테스트를 추적합니다."
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="일반적인 테스트 명령으로 Cargo 테스트 결과, 스위트 지속 시간 및 doctest를 추적합니다."
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Once"
    details="Once의 네이티브 통합을 통해 보고된 테스트 타겟, 스위트, 케이스, 실패 및 재시도 시도를 추적합니다."
    link="/guides/features/test-insights/once"
/>
</.home_cards>
