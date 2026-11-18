---
{
  "title": "테스트 샤딩",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 테스트 샤딩으로 여러 CI 러너에 테스트를 분산하여 테스트 스위트 속도를 높이세요."
}
---
# 테스트 샤딩 {#test-sharding}

최신 CI 호스트는 테스트 병렬화를 어느 정도 가능하게 하는 멀티코어 환경을 제공합니다. 하지만 단일 호스트가 제공할 수 있는 범위를 넘어서야 하는 시나리오도 있습니다. 예를 들어, 동시에 실행할 수 있는 시뮬레이터 수가 제한되거나 테스트 스위트가 단일 머신의 처리 능력을 초과하는 경우입니다.

이러한 경우 여러 CI 러너에 테스트를 분산하고 결과를 다시 통합된 뷰로 집계하는 시스템이 필요합니다. 테스트 샤딩이 바로 이 역할을 합니다.

Tuist는 [빈 패킹 알고리즘](https://en.wikipedia.org/wiki/Bin_packing_problem)을 사용해 과거 테스트 타이밍 데이터를 기반으로 샤드 간 부하를 지능적으로 균형 있게 분배하므로 각 러너가 거의 동일한 시간에 작업을 완료합니다. 모든 샤드의 결과는 <.localized_link href="/guides/features/test-insights">테스트 인사이트</.localized_link>에서 자동으로 집계되어 전체 샤드에 걸친 테스트 스위트를 하나의 통합된 뷰로 확인할 수 있습니다. 샤딩은 실제 소요 시간을 단축하지만 머신 시간은 증가시킬 수 있으며, [느린 테스트](https://tuist.dev/solutions/slow-tests)와 [CI 비용](https://tuist.dev/solutions/ci-costs)에서 두 요소를 어떻게 저울질해야 하는지 설명합니다.

<.home_cards>
  <.home_card
    title="Xcode"
    details="병렬 CI 러너에 걸쳐 Xcode 테스트를 샤딩합니다."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="생성된 프로젝트"
    details="Tuist가 생성한 프로젝트의 테스트를 병렬 CI 러너에 걸쳐 샤딩합니다."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="병렬 CI 러너에 걸쳐 Gradle 테스트를 샤딩합니다."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="Elixir 프로젝트의 테스트를 병렬 CI 러너에 걸쳐 샤딩합니다."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo 테스트 타겟을 병렬 CI 워커에 분산합니다."
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Once"
    details="호스팅 플랜에서 발견된 Once 테스트 배치를 CI 워커에 분산하고 결과를 결합합니다."
    link="/guides/features/test-sharding/once"
/>
</.home_cards>
