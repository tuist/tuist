---
{
  "title": "Покрытие кода",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Отслеживайте покрытие строк для каждого файла и коммита по результатам прогона тестов."
}
---
# Покрытие кода {#code-coverage}

Покрытие кода показывает, какие строки вашего кода были выполнены тестами. Tuist загружает данные о покрытии каждого запуска тестов и объединяет результаты всех запусков в рамках одного коммита в единую метрику — как для каждого файла, так и для всего проекта, чтобы вы могли отслеживать её на панели управления от коммита к коммиту.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Загружайте данные о покрытии кода проектов Xcode, протестированных с помощью tuist xcodebuild test."
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="Сгенерированные проекты"
    details="Измеряйте покрытие кода в проектах, сгенерированных Tuist, с помощью tuist test, бинарного кэша и выборочного тестирования."
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="Загружайте данные о построчном покрытии проектов Elixir, протестированных с помощью mix test --cover."
    link="/guides/features/test-code-coverage/elixir"
/>
</.home_cards>
