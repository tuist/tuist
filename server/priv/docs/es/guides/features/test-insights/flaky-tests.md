---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# Tests inestables {#flaky-tests}

Los tests inestables son tests que producen resultados diferentes (éxito o fallo) cuando se ejecutan varias veces con el mismo código. Minan la confianza en tu suite de tests y hacen perder tiempo a los desarrolladores investigando fallos falsos. Tuist detecta automáticamente los tests inestables y te ayuda a realizar un seguimiento de ellos a lo largo del tiempo.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Detecta, gestiona y aísla los tests inestables en proyectos de Xcode mediante tuist xcodebuild test."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="Proyectos generados"
    details="Detecta, gestiona y aísla los tests inestables en proyectos generados por Tuist mediante tuist test."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Detecta y gestiona los tests inestables en proyectos de Gradle."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="Detecta, silencia y omite los casos de test inestables de Bazel mediante tuist bazel test."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="Detecta y gestiona los tests inestables en proyectos de Elixir con reintentos de tests."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="Detecta e investiga los tests inestables de Cargo utilizando los resultados de las ejecuciones de CI."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
</.home_cards>
