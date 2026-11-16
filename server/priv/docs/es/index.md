---
{
  "title": "¿Qué es Tuist?",
  "description": "Tuist es una plataforma de compilación para equipos de ingeniería y sus agentes de programación. Admite flujos de trabajo de compilación y pruebas en Xcode, Gradle, Bazel, Elixir y Rust; el soporte para Once está en fase canary. Las funcionalidades varían según la cadena de herramientas y el almacenamiento en caché de compilaciones de Rust es experimental."
}
---

# Una plataforma de compilación para equipos y sus agentes de programación

**Tuist es una plataforma de compilación para equipos de ingeniería y sus agentes de programación.** Admite flujos de trabajo de compilación y tests en Xcode, Gradle, Bazel, Elixir y Rust; el soporte para Once está en fase canary. Funciona con los sistemas de compilación que ya utilizas, en lugar de reemplazarlos. Las funcionalidades disponibles dependen de tu toolchain: los proyectos Rust obtienen análisis de compilación y tests de Cargo, incluidos doctests, detección de tests inestables y caché de compilación experimental. Once se conecta de forma nativa para caché compartida, análisis de compilación y tests, sharding y vistas previas de aplicaciones compatibles.

Sigue una de las <.localized_link href="/guides/get-started">rutas de inicio</.localized_link> para tu sistema de compilación. Once se conecta directamente sin necesidad del CLI de Tuist; otras rutas explican qué herramientas de Tuist debes instalar.

<br/>

<.home_cards>
  <.home_card
    title="Caché"
    details="Comparte los resultados de compilación entre tu equipo y la CI. Funciona con la caché de compilación de Xcode, la caché de módulos de Tuist, la caché de compilación de Gradle, la caché remota de Bazel, la caché de dependencias de Elixir, la caché de compilación experimental de Rust y la caché de acciones compartida de Once."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="Análisis de compilación y tests"
    details="Haz seguimiento de la duración de compilaciones y tests, fallos, inestabilidad y regresiones en proyectos de Xcode, Gradle, Bazel, Elixir, Rust y Once."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="Tests selectivos"
    details="Ejecuta solo los tests afectados por un cambio en proyectos Xcode generados, para que el feedback llegue en segundos."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Runners"
    details="Ejecuta la CI en runners gestionados de macOS y Linux, cerca de la misma caché que usan las máquinas de tus desarrolladores."
    link="/guides/features/runners"
/>
  <.home_card
    title="Previews"
    details="Comparte tu app al instante con una URL. Sin demoras por revisión en la tienda, sin configuraciones complejas."
    link="/guides/features/previews"
/>
  <.home_card
    title="Proyectos generados"
    details="Describe proyectos Xcode en Swift y genéralos de forma consistente. Elimina conflictos de merge y desbloquea la caché de módulos."
    link="/guides/features/projects"
/>
  <.home_card
    title="Registro de paquetes"
    details="Resuelve paquetes Swift en segundos en lugar de minutos con un registro respaldado por la red de caché de Tuist."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Tamaño del bundle"
    details="Analiza y mantén tu app ligera para que los usuarios disfruten de descargas más rápidas y cumplas las directrices de las tiendas."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## Equipos que publican a escala confían en nosotros

**Los equipos de [Trendyol](https://www.trendyol.com/), [Etsy](https://www.etsy.com/), [Bumble](https://bumble.com/), [Monzo](https://monzo.com/), [Bending Spoons](https://bendingspoons.com/) y más de 100 empresas adicionales** publican mejoras más rápido con Tuist en sus bases de código iOS y Android.
