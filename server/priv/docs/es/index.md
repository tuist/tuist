---
{
  "title": "¿Qué es Tuist?",
  "description": "Un equipo de plataforma virtual para desarrolladores. Construye infraestructura para Xcode, Gradle, Bazel, Elixir y Rust, con funcionalidades adaptadas a cada cadena de herramientas."
}
---

# Un equipo de plataforma virtual para desarrolladores que publican software

**Tuist ayuda a los equipos a escalar el desarrollo de apps y publicar más rápido**, convirtiendo la complejidad de grandes bases de código en una experiencia productiva que crece con tu equipo. Funciona con los sistemas de compilación que ya usas, en proyectos de Xcode, Gradle, Bazel, Elixir y Rust. Las funcionalidades disponibles dependen de tu cadena de herramientas: los proyectos Rust obtienen análisis de compilación y tests de Cargo, incluidos doctests, detección de tests inestables y caché de compilación experimental.

Empieza <.localized_link href="/guides/install-tuist">instalando la interfaz de línea de comandos de Tuist</.localized_link>, luego sigue una de las <.localized_link href="/guides/get-started">rutas de inicio rápido</.localized_link> para tu sistema de compilación.

<br/>

<.home_cards>
  <.home_card
    title="Caché"
    details="Comparte los resultados de compilación entre tu equipo y la CI. Funciona con la caché de compilación de Xcode, la caché de módulos de Tuist, la caché de compilación de Gradle, la caché remota de Bazel y la caché de compilación experimental de Rust."
    supported_for="apple,gradle,bazel,rust"
    link="/guides/features/cache"
/>
  <.home_card
    title="Análisis de compilación y tests"
    details="Rastrea la duración de compilaciones y tests, fallos, inestabilidad y regresiones en proyectos de Xcode, Gradle, Bazel, Elixir y Rust."
    supported_for="apple,gradle,bazel,elixir,rust"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="Tests selectivos"
    details="Ejecuta solo los tests afectados por un cambio, en Xcode y proyectos generados, para que el feedback llegue en segundos."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Runners"
    details="Ejecuta la CI en runners gestionados de macOS y Linux, cerca de la misma caché que usan las máquinas de tus desarrolladores."
    link="/guides/features/runners"
/>
  <.home_card
    title="Previews"
    details="Comparte tu app al instante con una URL. Sin retrasos por revisión en la tienda, sin configuraciones complejas."
    link="/guides/features/previews"
/>
  <.home_card
    title="Proyectos generados"
    details="Describe proyectos de Xcode en Swift y genéralos de forma consistente. Elimina conflictos de merge y desbloquea la caché de módulos."
    link="/guides/features/projects"
/>
  <.home_card
    title="Registro de paquetes"
    details="Resuelve paquetes Swift en segundos en lugar de minutos con un registro respaldado por la red de caché de Tuist."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Tamaño del bundle"
    details="Analiza y mantén tu app ligera para que los usuarios tengan descargas más rápidas y cumplas las directrices de la tienda."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## Confiado por equipos que publican a escala

**Equipos de [Trendyol](https://www.trendyol.com/), [Etsy](https://www.etsy.com/), [Bumble](https://bumble.com/), [Monzo](https://monzo.com/), [Bending Spoons](https://bendingspoons.com/) y más de 100 empresas adicionales** publican más rápido con Tuist en sus bases de código iOS y Android.
