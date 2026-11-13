---
{
  "title": "코드 커버리지",
  "titleTemplate": ":title · 기능 · 가이드 · Tuist",
  "description": "테스트 실행에서 모든 파일과 커밋의 라인 커버리지를 추적합니다."
}
---
# 코드 커버리지 {#code-coverage}

코드 커버리지는 테스트가 코드의 어떤 줄을 실행했는지 보여줍니다. Tuist는 각 테스트 실행의 커버리지를 업로드하고 커밋의 실행 결과를 파일별 및 전체 프로젝트 기준으로 하나의 수치로 집계하므로, 대시보드에서 커밋별로 추이를 확인할 수 있습니다.

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test로 테스트한 Xcode 프로젝트의 코드 커버리지를 업로드합니다."
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="생성된 프로젝트"
    details="tuist test, 바이너리 캐시, 선택적 테스팅을 사용하여 Tuist가 생성한 프로젝트의 코드 커버리지를 측정합니다."
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="mix test --cover로 테스트한 Elixir 프로젝트의 라인 커버리지를 업로드합니다."
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="cargo test로 테스트한 Rust 프로젝트의 라인 커버리지를 업로드합니다."
    link="/guides/features/test-code-coverage/rust"
/>
</.home_cards>
