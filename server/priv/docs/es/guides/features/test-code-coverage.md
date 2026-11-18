---
{
  "title": "Cobertura de código",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Realiza un seguimiento de la cobertura de líneas de cada archivo y commit desde tus ejecuciones de tests."
}
---
# Cobertura de código {#code-coverage}

La cobertura de código te indica qué líneas de tu código ejecutaron tus tests. Tuist sube la cobertura de cada ejecución de tests y consolida las ejecuciones de un commit en una única cifra, por archivo y para todo el proyecto, para que puedas seguirla en el panel commit a commit.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Sube la cobertura de código de proyectos Xcode probados con tuist xcodebuild test."
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="Proyectos generados"
    details="Mide la cobertura de código en proyectos generados por Tuist con tuist test, la caché binaria y los tests selectivos."
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="Sube la cobertura de líneas de proyectos Elixir probados con mix test --cover."
    link="/guides/features/test-code-coverage/elixir"
/>
</.home_cards>
