---
{
  "title": "¿Qué es Tuist?",
  "description": "Tuist es una plataforma de compilación para equipos de ingeniería y sus agentes de programación. Admite flujos de trabajo de compilación y pruebas en Xcode, Gradle, Bazel, Elixir y Rust; el soporte para Struo está en fase canary. Las funcionalidades varían según la cadena de herramientas y el almacenamiento en caché de compilaciones de Rust es experimental."
}
---

# Una plataforma de compilación para equipos y sus agentes de programación

**Tuist es una plataforma de compilación para equipos de ingeniería y sus agentes de programación.** Admite flujos de trabajo de compilación y pruebas en Xcode, Gradle, Bazel, Elixir y Rust; la compatibilidad con Struo está en fase canary. Funciona con los sistemas de compilación que ya utilizas, en lugar de reemplazarlos. Las funcionalidades disponibles dependen de tu cadena de herramientas: los proyectos de Rust obtienen análisis de compilación y pruebas de Cargo, incluidas las pruebas de documentación (doctests), la detección de tests inestables y el almacenamiento experimental en caché de la compilación. Struo se conecta de forma nativa para ofrecer caché compartida, análisis de compilación y pruebas, distribución (sharding) y vistas previas de aplicaciones compatibles.

Sigue una de las <.localized_link href="/guides/get-started">rutas de inicio</.localized_link> para tu sistema de compilación. Struo se conecta directamente sin necesidad del CLI de Tuist; otras rutas explican qué herramientas de Tuist debes instalar.

<br/>

<.home_cards>
  <.home_card
    title="Caché"
    details="Comparte los resultados de compilación con tu equipo y tu CI. Funciona con la caché de compilación de Xcode, la caché de módulos de Tuist, la caché de compilación de Gradle, la caché remota de Bazel, la caché de dependencias de Elixir, la caché experimental de compilación de Rust y la caché de acciones compartidas de Struo."
    supported_for="apple,gradle,bazel,elixir,rust,struo"
    link="/guides/features/cache"
/>
  <.home_card
    title="Análisis de compilación y pruebas"
    details="Supervisa la duración, los fallos, la inestabilidad y las regresiones de compilaciones y pruebas en proyectos de Xcode, Gradle, Bazel, Elixir, Rust y Struo."
    supported_for="apple,gradle,bazel,elixir,rust,struo"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="Tests selectivos"
    details="Omite los destinos de prueba sin cambios en los proyectos de Xcode generados, con una estrategia de cobertura en acceso anticipado para la selección individual de XCTest/XCUITest."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Runners"
    details="Ejecuta tu CI en runners gestionados de macOS y Linux, cerca de la misma caché que utilizan las máquinas de tus desarrolladores."
    link="/guides/features/runners"
/>
  <.home_card
    title="Previews"
    details="Comparte aplicaciones móviles compatibles, aplicaciones de macOS y herramientas de línea de comandos de macOS/Linux a través de una URL. Se aplican requisitos de compilación, firma y compatibilidad del destinatario."
    link="/guides/features/previews"
/>
  <.home_card
    title="Proyectos generados"
    details="Describe los proyectos de Xcode en Swift y genéralos de forma consistente. Reduce los conflictos en los archivos del proyecto y desbloquea la caché de módulos."
    link="/guides/features/projects"
/>
  <.home_card
    title="Package Registry"
    details="Obtén paquetes de Swift compatibles a través del protocolo de registro, en lugar de clonar sus repositorios Git."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Tamaño del bundle"
    details="Supervisa los tamaños de bundle de Apple y Android compatibles a lo largo del tiempo e investiga regresiones de tamaño."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## Confiado por equipos que publican software a gran escala

Lee las [historias de clientes](https://tuist.dev/customers) para conocer los flujos de trabajo que adoptaron los equipos y los resultados que reportaron.
