---
{
  "title": "Análisis de compilaciones",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Supervisa el rendimiento de las compilaciones en proyectos de Xcode, Gradle, Bazel, Elixir, Rust y Struo con los análisis de compilaciones de Tuist."
}
---
# Análisis de compilaciones {#build-insights}

Usa el análisis de compilaciones para monitorizar el rendimiento de las compilaciones locales y en CI. Actualmente es compatible con Xcode, Gradle, Bazel, Elixir, Rust y Struo. Para una investigación paso a paso de las compilaciones lentas y el aumento de los costes de CI, consulta [Compilaciones lentas](https://tuist.dev/solutions/slow-builds) y [Costes de CI](https://tuist.dev/solutions/ci-costs).

<.home_cards>
  <.home_card
    title="Xcode"
    details="Monitoriza los tiempos de las acciones posteriores del esquema de Xcode, la configuración de compilación y los metadatos de compilación en el panel de Tuist."
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="Proyectos generados"
    details="Monitoriza el análisis de compilaciones en proyectos generados por Tuist con esquemas personalizados."
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Monitoriza el tiempo de las tareas de Gradle y la eficacia de la caché con el plugin de Gradle de Tuist."
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Monitoriza la duración de los comandos de Bazel, los totales de caché y el diagnóstico de la ruta crítica a través del protocolo de eventos de compilación."
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Monitoriza cuánto tarda en compilar tu proyecto de Elixir, sus advertencias y los archivos que ralentizan la compilación."
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Monitoriza la duración de los comandos de Cargo, las invocaciones observadas de rustc y el diagnóstico del compilador con la CLI de Tuist."
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Struo"
    details="Sigue las ejecuciones en directo e inspecciona las acciones del grafo, las duraciones, los fallos y las decisiones de caché."
    link="/guides/features/build-insights/struo"
/>
</.home_cards>
