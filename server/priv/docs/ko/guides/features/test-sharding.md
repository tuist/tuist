---
{
  "title": "테스트 샤딩",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 테스트 샤딩으로 여러 CI 러너에 테스트를 분산하여 테스트 스위트 속도를 높이세요."
}
---
# 테스트 샤딩 {#test-sharding}

최신 CI 호스트는 일정 수준의 테스트 병렬화를 허용하는 멀티코어 환경을 제공합니다. 그러나 단일 호스트가 제공할 수 있는 범위를 넘어서야 하는 상황이 있습니다. 예를 들어, 동시에 실행할 수 있는 시뮬레이터 수가 제한되거나 테스트 스위트가 단일 머신의 처리 능력을 초과하는 경우입니다.

이러한 경우 여러 CI 러너에 테스트를 분산하고 결과를 통합된 뷰로 집계하는 시스템이 필요합니다. 테스트 샤딩이 바로 이 역할을 수행합니다.

Tuist는 과거 테스트 소요 시간 데이터를 활용해 [빈 패킹 알고리즘](https://en.wikipedia.org/wiki/Bin_packing_problem)으로 샤드 간 부하를 지능적으로 균형 있게 분배하므로, 각 러너가 거의 동일한 시간에 작업을 완료합니다. 모든 샤드의 결과는 <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>에서 자동으로 집계되어, 모든 샤드에 걸친 테스트 스위트를 하나의 통합된 뷰로 확인할 수 있습니다.

<.home_cards>
  <.home_card
    title="Xcode"
    details="병렬 CI 러너에 걸쳐 Xcode 테스트를 샤딩합니다."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="생성된 프로젝트"
    details="병렬 CI 러너에 걸쳐 Tuist 생성 프로젝트의 테스트를 샤딩합니다."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="병렬 CI 러너에 걸쳐 Gradle 테스트를 샤딩합니다."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="병렬 CI 러너에 걸쳐 Elixir 프로젝트의 테스트를 샤딩합니다."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="병렬 CI 워커에 걸쳐 Cargo 테스트 타겟을 분산합니다."
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
