---
{
  "title": "빌드 인사이트",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 빌드 인사이트로 Xcode, Gradle, Bazel, Elixir, Rust, Once 프로젝트의 빌드 성능을 추적하세요."
}
---
# 빌드 인사이트 {#build-insights}

빌드 인사이트를 사용하여 로컬 및 CI 빌드 성능을 추적하세요. 현재 Xcode, Gradle, Bazel, Elixir, Rust, Once를 지원합니다. 느린 빌드와 증가하는 CI 비용을 단계별로 조사하려면 [느린 빌드](https://tuist.dev/solutions/slow-builds) 및 [CI 비용](https://tuist.dev/solutions/ci-costs)을 참조하세요.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Tuist 대시보드에서 Xcode 스킴 포스트 액션 시간, 빌드 설정 및 빌드 메타데이터를 추적합니다."
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="생성된 프로젝트"
    details="맞춤형 스킴이 포함된 Tuist 생성 프로젝트의 빌드 인사이트를 추적합니다."
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle 플러그인을 사용하여 Gradle 작업 시간과 캐시 효율성을 추적합니다."
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Build Event Protocol을 통해 Bazel 명령 지속 시간, 캐시 총합 및 중요 경로 진단을 추적합니다."
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Elixir 프로젝트의 컴파일 소요 시간, 경고 및 빌드를 지연시키는 파일을 추적합니다."
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Tuist CLI를 사용하여 Cargo 명령 지속 시간, 관찰된 rustc 호출 및 컴파일러 진단을 추적합니다."
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Once"
    details="실시간으로 실행을 추적하고 그래프 작업, 지속 시간, 실패 및 캐시 결정을 검사합니다."
    link="/guides/features/build-insights/once"
/>
</.home_cards>
