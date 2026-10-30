---
{
  "title": "Análisis de compilaciones",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Supervisa el rendimiento de las compilaciones para proyectos de Xcode, Gradle, Bazel, Elixir y Rust con los análisis de compilaciones de Tuist."
}
---
# Análisis de compilaciones {#build-insights}

Usa los análisis de compilaciones para seguir el rendimiento de las compilaciones locales y en CI. Actualmente es compatible con Xcode, Gradle, Bazel, Elixir y Rust.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Sigue los tiempos de las acciones posteriores al esquema de Xcode, la configuración de compilación y los metadatos de compilación en el panel de Tuist."
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="Proyectos generados"
    details="Sigue los análisis de compilación en los proyectos generados por Tuist con esquemas personalizados."
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Sigue la duración de las tareas de Gradle y la eficacia de la caché con el plugin de Gradle de Tuist."
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Sigue la duración de los comandos de Bazel, los totales de caché y los diagnósticos de la ruta crítica a través del protocolo de eventos de compilación."
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Sigue cuánto tarda en compilar tu proyecto de Elixir, sus advertencias y los archivos que ralentizan una compilación."
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Sigue la duración de los comandos de Cargo, las invocaciones observadas de rustc y los diagnósticos del compilador con la CLI de Tuist."
    link="/guides/features/build-insights/rust"
/>
</.home_cards>
