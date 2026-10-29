---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# Fragmentación de tests {#test-sharding}

Los hosts de CI modernos ofrecen entornos multinúcleo que permiten cierto grado de paralelización de tests. Sin embargo, hay escenarios en los que necesitas ir más allá de lo que un solo host puede ofrecer - por ejemplo, cuando estás limitado por el número de simuladores que puedes ejecutar simultáneamente, o cuando tu suite de tests simplemente supera la capacidad de una sola máquina.

En esos casos, necesitas un sistema que distribuya los tests entre múltiples runners de CI y agregue los resultados en una vista unificada. Eso es lo que hace la fragmentación de tests.

Tuist utiliza datos históricos de tiempos de ejecución de tests para equilibrar inteligentemente la carga entre fragmentos usando un [algoritmo de empaquetado en contenedores](https://en.wikipedia.org/wiki/Bin_packing_problem), de modo que cada runner termine aproximadamente al mismo tiempo. Los resultados de todos los fragmentos se agregan automáticamente en <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>, ofreciéndote una única vista unificada de tu suite de tests en todos los fragmentos.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Fragmenta tests de Xcode entre runners de CI en paralelo."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Proyectos generados"
    details="Fragmenta tests en proyectos generados por Tuist entre runners de CI en paralelo."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Fragmenta tests de Gradle entre runners de CI en paralelo."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="Fragmenta los tests de tu proyecto Elixir entre runners de CI en paralelo."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Distribuye objetivos de test de Cargo entre workers de CI en paralelo."
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
