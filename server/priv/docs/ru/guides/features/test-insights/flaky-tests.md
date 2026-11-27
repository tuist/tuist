---
{
  "title": "Нестабильные тесты",
  "titleTemplate": ":title · Аналитика тестов · Возможности · Руководства · Tuist",
  "description": "Автоматически обнаруживайте и отслеживайте нестабильные тесты в ваших CI-пайплайнах."
}
---
# Нестабильные тесты {#flaky-tests}

Нестабильные тесты — это тесты, которые при многократном запуске с одним и тем же кодом дают разные результаты (проходят или падают). Они подрывают доверие к набору тестов и отнимают время разработчиков на расследование ложных сбоев. Tuist автоматически обнаруживает нестабильные тесты и помогает отслеживать их со временем. О том, как исследовать и изолировать такие тесты в команде, см. [Нестабильные тесты](https://tuist.dev/solutions/flaky-tests). Независимое от инструментов объяснение распространенных причин и способов измерения нестабильности см. в <.localized_link href="/references/concepts/flaky-test">Что такое нестабильный тест?</.localized_link>.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Обнаруживайте, управляйте и помещайте в карантин нестабильные тесты в проектах Xcode через tuist xcodebuild test."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="Сгенерированные проекты"
    details="Обнаруживайте, управляйте и помещайте в карантин нестабильные тесты в сгенерированных Tuist проектах через tuist test."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Обнаруживайте и управляйте нестабильными тестами в проектах Gradle."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="Обнаруживайте, игнорируйте сбои и пропускайте нестабильные тест-кейсы Bazel через tuist bazel test."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="Обнаруживайте и управляйте нестабильными тестами в проектах Elixir с помощью повторных запусков тестов."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="Обнаруживайте и исследуйте нестабильные тесты Cargo, используя результаты нескольких запусков CI."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Struo"
    details="Исследуйте несогласованные результаты тестов через отчеты о повторных попытках и историю CI."
    link="/guides/features/test-insights/flaky-tests/struo"
/>
</.home_cards>
