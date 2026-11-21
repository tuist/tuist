---
{
  "title": "Аналитика тестов",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Выявляйте нестабильные и медленные тесты в проектах на Xcode, Gradle, Bazel, Elixir, Rust и Struo с помощью аналитики тестов Tuist."
}
---
# Аналитика тестов {#test-insights}

Используйте аналитику тестов, чтобы следить за состоянием набора тестов: выявлять медленные тесты, отслеживать нестабильные тесты и быстро разбираться в причинах сбоев CI-запусков. Сейчас поддерживаются Xcode, Gradle, Bazel, Elixir, Rust и Struo. Доступные результаты и временные метрики зависят от вашего раннера. Чтобы видеть, какой код выполняют ваши тесты в поддерживаемых системах сборки, см. <.localized_link href="/guides/features/test-code-coverage">Покрытие кода</.localized_link>. Рекомендации по [медленным тестам](https://tuist.dev/solutions/slow-tests) и [нестабильным тестам](https://tuist.dev/solutions/flaky-tests) смотрите в руководствах по решениям.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Отслеживайте аналитику тестов Xcode с помощью постдействий схемы и CLI Tuist."
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Отслеживайте аналитику тестов Gradle с помощью плагина Tuist для Gradle."
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Отслеживайте аналитику тестов Bazel, запуская тесты через tuist bazel test."
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Отслеживайте тесты вашего проекта на Elixir с помощью пакета Tuist для Hex."
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Отслеживайте результаты тестов Cargo, длительность наборов и doctests, используя вашу обычную команду тестирования."
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Struo"
    details="Отслеживайте сообщаемые цели тестов, наборы, случаи, сбои и попытки повторного запуска через нативную интеграцию Struo."
    link="/guides/features/test-insights/struo"
/>
</.home_cards>
