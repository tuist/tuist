---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# Распараллеливание тестов {#test-sharding}

Современные хосты CI предоставляют многоядерные среды, которые позволяют в определенной степени параллелизовать выполнение тестов. Однако бывают ситуации, когда возможностей одного хоста недостаточно — например, когда вы ограничены количеством симуляторов, которые можно запускать одновременно, или когда ваш набор тестов просто перерастает возможности одной машины.

В таких случаях вам нужна система, которая распределяет тесты между несколькими раннерами CI и агрегирует результаты в единое представление. Именно этим занимается распараллеливание тестов.

Tuist использует исторические данные о времени выполнения тестов, чтобы интеллектуально балансировать нагрузку между шардами с помощью [алгоритма упаковки в контейнеры](https://en.wikipedia.org/wiki/Bin_packing_problem), благодаря чему каждый раннер завершает работу примерно в одно и то же время. Результаты со всех шардов автоматически агрегируются в разделе <.localized_link href="/guides/features/test-insights">Аналитика тестов</.localized_link>, предоставляя единое представление о вашем наборе тестов по всем шардам.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Распараллеливайте тесты Xcode между параллельными раннерами CI."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Генерируемые проекты"
    details="Распараллеливайте тесты в генерируемых проектах Tuist между параллельными раннерами CI."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Распараллеливайте тесты Gradle между параллельными раннерами CI."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="Распараллеливайте тесты вашего проекта на Elixir между параллельными раннерами CI."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Узнайте о доступности распараллеливания тестов для обычных запусков тестов Cargo."
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
