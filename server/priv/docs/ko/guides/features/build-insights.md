---
{
  "title": "빌드 인사이트",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "Tuist 빌드 인사이트로 Xcode, Gradle, Bazel, Elixir, Rust 프로젝트의 빌드 성능을 추적하세요."
}
---
# 빌드 인사이트 {#build-insights}

빌드 인사이트를 사용해 로컬 및 CI 빌드 성능을 추적하세요. 현재 Xcode, Gradle, Bazel, Elixir, Rust를 지원합니다.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Tuist 대시보드에서 Xcode 스킴의 포스트 액션 시간, 빌드 설정, 빌드 메타데이터를 추적합니다."
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="생성된 프로젝트"
    details="Tuist로 생성된 프로젝트에서 커스텀 스킴을 사용한 빌드 인사이트를 추적합니다."
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle 플러그인으로 Gradle 작업 시간과 캐시 효율성을 추적합니다."
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Build Event Protocol을 통해 Bazel 명령 실행 시간, 캐시 총량, 크리티컬 경로 진단 정보를 추적합니다."
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Elixir 프로젝트의 컴파일 소요 시간, 경고, 빌드를 지연시키는 파일을 추적합니다."
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Tuist CLI로 Cargo 명령 실행 시간, 관찰된 rustc 호출, 컴파일러 진단 정보를 추적합니다."
    link="/guides/features/build-insights/rust"
/>
</.home_cards>
