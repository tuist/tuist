---
{
  "title": "Análisis de tests",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Identifica tests inestables y lentos en proyectos de Xcode, Gradle, Bazel, Elixir, Rust y Once con los análisis de tests de Tuist."
}
---
# Análisis de tests {#test-insights}

Usa el análisis de tests para supervisar la salud de tu suite de tests identificando tests lentos, rastreando tests inestables y comprendiendo rápidamente las ejecuciones de CI fallidas. Actualmente es compatible con Xcode, Gradle, Bazel, Elixir, Rust y Once. Los resultados y los tiempos disponibles dependen de tu runner. Para saber qué código ejecutan tus tests en los sistemas de compilación compatibles, consulta <.localized_link href="/guides/features/test-code-coverage">Cobertura de código</.localized_link>.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Rastrea las métricas de tests de Xcode usando post-acciones del esquema y la CLI de Tuist."
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Rastrea las métricas de tests de Gradle con el plugin de Gradle de Tuist."
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Rastrea las métricas de tests de Bazel ejecutando tests mediante tuist bazel test."
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
    title="Once"
    details="Rastrea los targets de test reportados, las suites, los casos, los fallos y los intentos de reintento a través de la integración nativa de Once."
    link="/guides/features/test-insights/once"
/>
</.home_cards>
