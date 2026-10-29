---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# 불안정한 테스트 {#flaky-tests}

불안정한 테스트는 동일한 코드로 여러 번 실행했을 때 서로 다른 결과(통과 또는 실패)를 내는 테스트입니다. 이러한 테스트는 테스트 스위트에 대한 신뢰를 떨어뜨리고, 잘못된 실패를 조사하는 데 개발자의 시간을 낭비하게 만듭니다. Tuist는 불안정한 테스트를 자동으로 감지하고 시간에 따라 추적할 수 있도록 도와줍니다.

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test를 통해 Xcode 프로젝트에서 불안정한 테스트를 감지, 관리 및 격리합니다."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="생성된 프로젝트"
    details="tuist test를 통해 Tuist가 생성한 프로젝트에서 불안정한 테스트를 감지, 관리 및 격리합니다."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle 프로젝트에서 불안정한 테스트를 감지하고 관리합니다."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test를 통해 불안정한 Bazel 테스트 케이스를 감지, 음소거 및 건너뜁니다."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="테스트 재시도를 통해 Elixir 프로젝트에서 불안정한 테스트를 감지하고 관리합니다."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="CI 실행 간 결과를 사용하여 불안정한 Cargo 테스트를 감지하고 조사합니다."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
</.home_cards>
