---
{
  "title": "¿Qué es Tuist?",
  "description": "Tuist es una plataforma de compilación para equipos de ingeniería y sus agentes de programación. Admite flujos de trabajo de compilación y pruebas en Xcode, Gradle, Bazel, Elixir y Rust; el soporte para Once está en fase canary. Las funcionalidades varían según la cadena de herramientas y el almacenamiento en caché de compilaciones de Rust es experimental."
}
---

# Una plataforma de compilación para equipos y sus agentes de programación

**Tuist es una plataforma de compilación para equipos de ingeniería y sus agentes de programación.** Admite flujos de trabajo de compilación y tests en Xcode, Gradle, Bazel, Elixir y Rust; el soporte para Once está en fase canary. Funciona con los sistemas de compilación que ya utilizas, en lugar de reemplazarlos. Las funcionalidades disponibles dependen de tu cadena de herramientas: los proyectos Rust obtienen análisis de compilación y tests de Cargo, incluidos doctests, detección de tests inestables y caché de compilación experimental. Once se conecta de forma nativa para caché compartida, análisis de compilación y tests, distribución de tareas (sharding) y vistas previas de aplicaciones compatibles.

Sigue una de las <.localized_link href="/guides/get-started">rutas de inicio</.localized_link> para tu sistema de compilación. Once se conecta directamente sin necesidad del CLI de Tuist; otras rutas explican qué herramientas de Tuist debes instalar.

<br/>

<.home_cards>
  <.home_card
    title="Caché"
    details="Comparte los resultados de compilación entre tu equipo y la CI. Funciona con la caché de compilación de Xcode, la caché de módulos de Tuist, la caché de compilación de Gradle, la caché remota de Bazel, la caché de dependencias de Elixir, la caché de compilación experimental de Rust y la caché de acciones compartidas de Once."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="Análisis de compilación y tests"
    details="Supervisa la duración de compilaciones y tests, fallos, inestabilidad y regresiones en proyectos de Xcode, Gradle, Bazel, Elixir, Rust y Once."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="Tests selectivos"
    details="Omite los targets de test sin cambios en proyectos Xcode generados, con una estrategia de cobertura en acceso anticipado para la selección individual de XCTest/XCUITest."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Runners"
    details="Ejecuta la CI en runners gestionados de macOS y Linux, cerca de la misma caché que usan las máquinas de tus desarrolladores."
    link="/guides/features/runners"
/>
  <.home_card
    title="Vistas previas"
    details="Comparte aplicaciones móviles compatibles, aplicaciones de macOS y herramientas de línea de comandos de macOS/Linux a través de una URL. Se aplican requisitos de compilación, firma y compatibilidad del destinatario."
    link="/guides/features/previews"
/>
  <.home_card
    title="Proyectos generados"
    details="Describe proyectos de Xcode en Swift y genéralos de forma consistente. Reduce los conflictos en los archivos de proyecto y desbloquea la caché de módulos."
    link="/guides/features/projects"
/>
  <.home_card
    title="Registro de paquetes"
    details="Obtén paquetes Swift compatibles a través del protocolo de registro en lugar de clonar sus repositorios Git."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Tamaño del bundle"
    details="Supervisa los tamaños de bundle compatibles de Apple y Android a lo largo del tiempo e investiga regresiones de tamaño."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## Con la confianza de equipos que publican mejoras a gran escala

Lee las [historias de clientes](https://tuist.dev/customers) para conocer los flujos de trabajo que adoptaron los equipos y los resultados que reportaron.
