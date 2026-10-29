---
{
  "title": "Get started",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Pick the Tuist path that matches how your app is built today: Xcode, generated Xcode projects, Gradle, Elixir, Rust, or Bazel."
}
---
# Comenzar {#get-started}

Elige la ruta que se adapte a cómo está construida tu app hoy. Cada una te guía paso a paso sobre qué instalar, cómo habilitar el almacenamiento en caché, las funcionalidades de análisis y pruebas, y cómo verificar la configuración de extremo a extremo. Puedes adoptarlas de forma independiente o combinarlas si distribuyes en más de una plataforma.

## Proyecto de Xcode {#existing-xcode-project}

Mantén tu proyecto o espacio de trabajo de Xcode existente y añade las capacidades de Tuist una por una. No es necesaria la generación del proyecto.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Proyecto de Xcode generado {#generated-xcode-project}

Permite que Tuist defina y genere tu proyecto de Xcode a partir de manifiestos Swift. Los proyectos generados condensan la complejidad de los proyectos modulares de Xcode en una descripción concisa y declarativa del grafo, y son un requisito estricto para la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> y las <.localized_link href="/guides/features/selective-testing/generated-xcode-project">pruebas selectivas</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Proyecto de Gradle {#gradle-project}

Conecta un proyecto de Gradle a la caché remota de Tuist, así como a sus análisis de compilación y de pruebas, mediante el plugin de Gradle `dev.tuist`.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Proyecto de Elixir {#elixir-project}

Conecta un proyecto de Elixir a los análisis de compilación y pruebas de Tuist, a la detección de tests inestables y al sharding de tests mediante el paquete Hex `tuist_ex`.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Proyecto de Rust {#rust-project}

Ejecuta Cargo a través de la CLI de Tuist para informar de las compilaciones y de los resultados individuales de tests, incluidos los doctests, e investigar tests inestables.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Proyecto de Bazel {#bazel-project}

Apunta un espacio de trabajo de Bazel a la caché de la API de Ejecución Remota de Tuist y al Servicio de Eventos de Compilación para compartir aciertos de caché y análisis entre tu equipo y la CI.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

Antes de cualquiera de estas opciones, <.localized_link href="/guides/install-tuist">instala la interfaz de línea de comandos de Tuist</.localized_link>. Los proyectos de Elixir son la excepción: solo necesitan el paquete Hex.
