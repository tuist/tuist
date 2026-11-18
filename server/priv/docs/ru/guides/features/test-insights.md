---
{
  "title": "Аналитика тестов",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Выявляйте нестабильные и медленные тесты в проектах Xcode, Gradle, Bazel, Elixir, Rust и Once с помощью аналитики тестов Tuist."
}
---
# Аналитика тестов {#test-insights}

Используйте аналитику тестов, чтобы отслеживать состояние вашего набора тестов: выявляйте медленные тесты, контролируйте нестабильные тесты и быстро разбирайтесь в причинах сбоев в CI. Сейчас поддерживаются Xcode, Gradle, Bazel, Elixir, Rust и Once. Доступные результаты и замеры времени зависят от используемого раннера. Чтобы понять, какой код выполняется вашими тестами в поддерживаемых системах сборки, см. <.localized_link href="/guides/features/test-code-coverage">Покрытие кода</.localized_link>. Рекомендации по [медленным тестам](https://tuist.dev/solutions/slow-tests) и [нестабильным тестам](https://tuist.dev/solutions/flaky-tests) вы найдете в руководствах по решениям.

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
    details="Отслеживайте зарегистрированные цели тестирования, наборы, случаи, сбои и попытки повторного запуска через нативную интеграцию Once."
    link="/guides/features/test-insights/once"
/>
</.home_cards>
