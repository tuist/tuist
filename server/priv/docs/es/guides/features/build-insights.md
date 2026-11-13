---
{
  "title": "Análisis de compilaciones",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Supervisa el rendimiento de las compilaciones para proyectos de Xcode, Gradle, Bazel, Elixir, Rust y Once con los análisis de compilaciones de Tuist."
}
---
# Análisis de compilaciones {#build-insights}

Usa el análisis de compilaciones para supervisar el rendimiento de las compilaciones locales y en CI. Actualmente es compatible con Xcode, Gradle, Bazel, Elixir, Rust y Once. Para investigar paso a paso las compilaciones lentas y el aumento de los costes de CI, consulta [Compilaciones lentas](https://tuist.dev/solutions/slow-builds) y [Costes de CI](https://tuist.dev/solutions/ci-costs).

<.home_cards>
  <.home_card
    title="Xcode"
    details="Supervisa los tiempos posteriores a la acción del esquema de Xcode, la configuración de compilación y los metadatos de compilación en el panel de Tuist."
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="Proyectos generados"
    details="Supervisa el análisis de compilaciones en proyectos generados por Tuist con esquemas personalizados."
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Supervisa la duración de las tareas de Gradle y la eficacia de la caché con el plugin de Gradle de Tuist."
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Supervisa la duración de los comandos de Bazel, los totales de caché y los diagnósticos de la ruta crítica mediante el protocolo Build Event Protocol."
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Supervisa cuánto tarda en compilar tu proyecto de Elixir, sus advertencias y los archivos que ralentizan la compilación."
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Supervisa la duración de los comandos de Cargo, las invocaciones observadas de rustc y los diagnósticos del compilador con la CLI de Tuist."
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Once"
    details="Sigue las ejecuciones en directo e inspecciona las acciones del grafo, las duraciones, los fallos y las decisiones de caché."
    link="/guides/features/build-insights/once"
/>
</.home_cards>
