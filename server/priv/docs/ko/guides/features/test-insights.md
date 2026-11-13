---
{
  "title": "테스트 인사이트",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 테스트 인사이트로 Xcode, Gradle, Bazel, Elixir, Rust 및 Once 프로젝트에서 불안정하거나 느린 테스트를 식별하세요."
}
---
# 테스트 인사이트 {#test-insights}

느린 테스트 식별, 불안정한 테스트 추적, 실패한 CI 실행의 빠른 분석을 통해 테스트 스위트의 상태를 모니터링하려면 테스트 인사이트를 사용하세요. 현재 Xcode, Gradle, Bazel, Elixir, Rust, Once를 지원합니다. 제공되는 결과와 타이밍은 러너에 따라 달라집니다. 지원되는 빌드 시스템에서 테스트가 실행하는 코드를 확인하려면 <.localized_link href="/guides/features/test-code-coverage">코드 커버리지</.localized_link>를 참조하세요.

<.home_cards>
  <.home_card
    title="Xcode"
    details="스킴 포스트 액션과 Tuist CLI를 사용하여 Xcode 테스트 분석 정보를 추적합니다."
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle 플러그인을 사용하여 Gradle 테스트 분석 정보를 추적합니다."
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test를 통해 테스트를 실행하여 Bazel 테스트 분석 정보를 추적합니다."
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Tuist Hex 패키지를 사용하여 Elixir 프로젝트의 테스트를 추적합니다."
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="일반적인 테스트 명령어로 Cargo 테스트 결과, 스위트 소요 시간, doctest를 추적합니다."
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Once"
    details="Once의 네이티브 통합을 통해 보고된 테스트 대상, 스위트, 케이스, 실패 및 재시도 횟수를 추적합니다."
    link="/guides/features/test-insights/once"
/>
</.home_cards>
