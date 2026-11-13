---
{
  "title": "Tests inestables",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Detecta y rastrea automáticamente los tests inestables en tus pipelines de CI."
}
---
# Tests inestables {#flaky-tests}

Los tests inestables son tests que producen resultados diferentes (aprobado o fallido) al ejecutarse varias veces con el mismo código. Minan la confianza en tu suite de tests y hacen perder tiempo a los desarrolladores investigando fallos falsos. Tuist detecta automáticamente los tests inestables y te ayuda a seguirlos a lo largo del tiempo. Para saber cómo investigarlos y contenerlos como equipo, consulta [Tests inestables](https://tuist.dev/solutions/flaky-tests).

<.home_cards>
  <.home_card
    title="Xcode"
    details="Detecta, gestiona y aísla tests inestables en proyectos de Xcode mediante tuist xcodebuild test."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="Proyectos generados"
    details="Detecta, gestiona y aísla tests inestables en proyectos generados por Tuist mediante tuist test."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Detecta y gestiona tests inestables en proyectos de Gradle."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="Detecta, silencia y omite casos de test inestables de Bazel mediante tuist bazel test."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="Detecta y gestiona tests inestables en proyectos de Elixir con reintentos de test."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="Detecta e investiga tests inestables de Cargo usando resultados entre ejecuciones de CI."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="Investiga resultados de test inconsistentes a través de los intentos de reintento reportados y el historial de CI."
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
