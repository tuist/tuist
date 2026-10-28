---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# Сегментация тестов {#test-sharding}

Современные хосты CI предоставляют многоядерные среды, которые позволяют в определенной степени параллелизовать выполнение тестов. Однако бывают ситуации, когда возможностей одного хоста недостаточно — например, когда вы ограничены количеством симуляторов, которые можно запустить одновременно, или когда ваш набор тестов просто перерастает возможности одной машины.

В таких случаях вам нужна система, которая распределяет тесты по нескольким раннерам CI и объединяет результаты в единое представление. Именно этим занимается сегментация тестов.

Tuist использует исторические данные о времени выполнения тестов, чтобы интеллектуально сбалансировать нагрузку между сегментами с помощью [алгоритма упаковки в контейнеры](https://en.wikipedia.org/wiki/Bin_packing_problem), благодаря чему каждый раннер завершает работу примерно в одно и то же время. Результаты со всех сегментов автоматически агрегируются в разделе <.localized_link href="/guides/features/test-insights">Аналитика тестов</.localized_link>, предоставляя вам единое представление о вашем наборе тестов по всем сегментам.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Распределяйте тесты Xcode по параллельным раннерам CI."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Сгенерированные проекты"
    details="Распределяйте тесты в сгенерированных проектах Tuist по параллельным раннерам CI."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Распределяйте тесты Gradle по параллельным раннерам CI."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="Распределяйте тесты вашего проекта на Elixir по параллельным раннерам CI."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Распределяйте цели тестирования Cargo по параллельным воркерам CI."
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
