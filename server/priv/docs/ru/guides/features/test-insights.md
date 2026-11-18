---
{
  "title": "Аналитика тестов",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Выявляйте нестабильные и медленные тесты в проектах Xcode, Gradle, Bazel, Elixir, Rust и Once с помощью аналитики тестов Tuist."
}
---
# Аналитика тестов {#test-insights}

Используйте аналитику тестов, чтобы отслеживать состояние набора тестов: выявлять медленные тесты, контролировать нестабильные тесты и быстро разбираться с причинами сбоев в CI. Сейчас поддерживаются Xcode, Gradle, Bazel, Elixir, Rust и Once. Доступные результаты и замеры времени зависят от вашего раннера. Чтобы понять, какой код выполняют ваши тесты в поддерживаемых системах сборки, см. <.localized_link href="/guides/features/test-code-coverage">Покрытие кода</.localized_link>.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Отслеживайте аналитику тестов Xcode с помощью пост-действий схем и CLI Tuist."
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
    details="Отслеживайте результаты тестов Cargo, длительность наборов и doctests, используя вашу обычную команду запуска тестов."
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Once"
    details="Отслеживайте зарегистрированные цели тестирования, наборы, кейсы, сбои и попытки повторного запуска через нативную интеграцию Once."
    link="/guides/features/test-insights/once"
/>
</.home_cards>
