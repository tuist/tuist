---
{
  "title": "Аналитика сборок",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Отслеживайте производительность сборок для проектов Xcode, Gradle, Bazel, Elixir, Rust и Once с помощью аналитики сборок Tuist."
}
---
# Аналитика сборок {#build-insights}

Используйте аналитику сборок для отслеживания производительности локальных сборок и сборок в CI. Сейчас поддерживаются Xcode, Gradle, Bazel, Elixir, Rust и Once.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Отслеживайте время выполнения пост-действий схем Xcode, настройки сборки и метаданные сборки в панели управления Tuist."
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="Сгенерированные проекты"
    details="Отслеживайте аналитику сборок в сгенерированных проектах Tuist с пользовательскими схемами."
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Отслеживайте время выполнения задач Gradle и эффективность кэширования с помощью плагина Tuist для Gradle."
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Отслеживайте длительность команд Bazel, общие показатели кэша и диагностику критического пути через протокол событий сборки (Build Event Protocol)."
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Отслеживайте время компиляции вашего проекта на Elixir, предупреждения и файлы, которые замедляют сборку."
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Отслеживайте длительность команд Cargo, зафиксированные вызовы rustc и диагностику компилятора с помощью CLI Tuist."
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Once"
    details="Следите за запусками в реальном времени и анализируйте действия графа, их длительность, сбои и решения кэширования."
    link="/guides/features/build-insights/once"
/>
</.home_cards>
