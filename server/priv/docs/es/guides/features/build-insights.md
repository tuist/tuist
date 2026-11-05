---
{
  "title": "Análisis de compilaciones",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Supervisa el rendimiento de las compilaciones en proyectos de Xcode, Gradle, Bazel, Elixir y Rust con los análisis de compilaciones de Tuist."
}
---
# Análisis de compilaciones {#build-insights}

Usa el análisis de compilaciones para rastrear el rendimiento de las compilaciones locales y en CI. Actualmente es compatible con Xcode, Gradle, Bazel, Elixir y Rust.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Rastrea los tiempos de las acciones posteriores al esquema de Xcode, la configuración de compilación y los metadatos de compilación en el panel de Tuist."
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="Proyectos generados"
    details="Rastrea el análisis de compilaciones en proyectos generados por Tuist con esquemas personalizados."
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Rastrea la duración de las tareas de Gradle y la eficacia de la caché con el plugin de Gradle de Tuist."
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Rastrea la duración de los comandos de Bazel, los totales de caché y el diagnóstico de la ruta crítica a través del protocolo de eventos de compilación."
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Rastrea cuánto tarda en compilar tu proyecto de Elixir, sus advertencias y los archivos que ralentizan la compilación."
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Rastrea la duración de los comandos de Cargo, las invocaciones observadas de rustc y el diagnóstico del compilador con la CLI de Tuist."
    link="/guides/features/build-insights/rust"
/>
</.home_cards>
