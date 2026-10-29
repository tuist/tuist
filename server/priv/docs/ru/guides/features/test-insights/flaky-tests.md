---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# Нестабильные тесты {#flaky-tests}

Нестабильные тесты — это тесты, которые дают разные результаты (успех или неудача) при многократном запуске с одним и тем же кодом. Они подрывают доверие к вашему набору тестов и отнимают время разработчиков на расследование ложных сбоев. Tuist автоматически обнаруживает нестабильные тесты и помогает отслеживать их со временем.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Обнаруживайте, управляйте и изолируйте нестабильные тесты в проектах Xcode с помощью tuist xcodebuild test."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="Сгенерированные проекты"
    details="Обнаруживайте, управляйте и изолируйте нестабильные тесты в сгенерированных Tuist проектах с помощью tuist test."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Обнаруживайте и управляйте нестабильными тестами в проектах Gradle."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="Обнаруживайте, отключайте и пропускайте нестабильные тестовые случаи Bazel через tuist bazel test."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="Обнаруживайте и управляйте нестабильными тестами в проектах Elixir с повторными запусками тестов."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="Обнаруживайте и исследуйте нестабильные тесты Cargo, используя результаты нескольких запусков CI."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
</.home_cards>
