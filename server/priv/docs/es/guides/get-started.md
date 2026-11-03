---
{
  "title": "Primeros pasos",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Elige la ruta de Tuist que se ajuste a cómo está construida tu app hoy: Xcode, proyectos de Xcode generados, Gradle, Elixir, Rust o Bazel."
}
---
# Primeros pasos {#get-started}

Elige la ruta que se adapte a cómo está construida tu app hoy. Cada una te guía sobre qué instalar, cómo habilitar las funcionalidades de caché, análisis y tests, y cómo verificar la configuración de extremo a extremo. Puedes adoptarlas de forma independiente o combinarlas si publicas en más de una plataforma.

## Proyecto de Xcode {#existing-xcode-project}

Mantén tu proyecto o espacio de trabajo de Xcode existente y añade las funcionalidades de Tuist una a una. No es necesario generar el proyecto.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Proyecto de Xcode generado {#generated-xcode-project}

Permite que Tuist defina y genere tu proyecto de Xcode a partir de manifiestos en Swift. Los proyectos generados condensan la complejidad de los proyectos modulares de Xcode en una descripción concisa y declarativa del grafo, y son un requisito indispensable para la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> y los <.localized_link href="/guides/features/selective-testing/generated-xcode-project">tests selectivos</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Proyecto de Gradle {#gradle-project}

Conecta un proyecto de Gradle a la caché remota, al análisis de compilaciones y al análisis de tests de Tuist mediante el `dev.tuist` plugin de Gradle.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Proyecto de Elixir {#elixir-project}

Conecta un proyecto de Elixir al análisis de compilaciones, al análisis de tests, a la detección de tests inestables y al reparto de tests (sharding) de Tuist mediante el paquete Hex `tuist_ex`.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Proyecto de Rust {#rust-project}

Ejecuta Cargo a través de la CLI de Tuist para informar de las compilaciones y de los resultados de tests individuales, incluidos los doctests, e investigar tests inestables.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Proyecto de Bazel {#bazel-project}

Apunta un espacio de trabajo de Bazel a la caché de la API de ejecución remota y al servicio de eventos de compilación de Tuist para compartir aciertos de caché y análisis con tu equipo y tu CI.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

Antes de cualquiera de estas opciones, <.localized_link href="/guides/install-tuist">instala la interfaz de línea de comandos de Tuist</.localized_link>. Los proyectos de Elixir son la excepción: solo necesitan el paquete Hex.
