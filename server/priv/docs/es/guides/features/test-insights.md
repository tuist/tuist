---
{
  "title": "Análisis de tests",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Identifica tests inestables y lentos en proyectos de Xcode, Gradle, Bazel, Elixir, Rust y Struo con los análisis de tests de Tuist."
}
---
# Análisis de tests {#test-insights}

Usa el análisis de tests para supervisar la salud de tu suite de tests identificando tests lentos, rastreando tests inestables y comprendiendo rápidamente las ejecuciones de CI fallidas. Actualmente es compatible con Xcode, Gradle, Bazel, Elixir, Rust y Struo. Los resultados y tiempos disponibles dependen de tu runner. Para saber qué código ejecutan tus tests en los sistemas de compilación compatibles, consulta <.localized_link href="/guides/features/test-code-coverage">Cobertura de código</.localized_link>. Para obtener orientación sobre [tests lentos](https://tuist.dev/solutions/slow-tests) y [tests inestables](https://tuist.dev/solutions/flaky-tests), consulta las guías de soluciones.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Rastrea las analíticas de tests de Xcode mediante post-acciones de esquemas y la CLI de Tuist."
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Rastrea las analíticas de tests de Gradle con el plugin de Tuist para Gradle."
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Rastrea las analíticas de tests de Bazel ejecutando los tests a través de tuist bazel test."
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Rastrea los tests de tu proyecto de Elixir con el paquete Hex de Tuist."
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Rastrea los resultados de los tests de Cargo, las duraciones de las suites y los doctests con tu comando de test habitual."
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Struo"
    details="Rastrea los targets de test reportados, suites, casos, fallos e intentos de reintento a través de la integración nativa de Struo."
    link="/guides/features/test-insights/struo"
/>
</.home_cards>
