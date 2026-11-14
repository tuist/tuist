---
{
  "title": "Primeros pasos",
  "titleTemplate": ":title · Guías · Tuist",
  "description": "Elige la ruta de Tuist que se ajuste a cómo se construye tu app hoy: Xcode, proyectos de Xcode generados, Gradle, Elixir, Rust, Bazel u Once."
}
---
# Comienza {#get-started}

Elige la ruta que se ajuste a cómo está construida tu app hoy. Cada una te guía paso a paso sobre qué instalar, cómo habilitar las funcionalidades de caché, análisis y tests, y cómo verificar la configuración de extremo a extremo. Puedes adoptarlas por separado o combinarlas si publicas en más de una plataforma.

La mayoría de las rutas usan la <.localized_link href="/guides/install-tuist">interfaz de línea de comandos de Tuist</.localized_link>. Elixir utiliza el paquete Hex, y Once se conecta mediante su proveedor nativo de Tuist; ninguno requiere la CLI de Tuist para su integración.

## Proyecto de Xcode {#existing-xcode-project}

Mantén tu proyecto o espacio de trabajo de Xcode existente y añade las funcionalidades de Tuist una a una. No es necesario generar el proyecto.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Proyecto de Xcode generado {#generated-xcode-project}

Permite que Tuist defina y genere tu proyecto de Xcode a partir de manifiestos Swift. Los proyectos generados reducen la complejidad de los proyectos modulares de Xcode a una descripción concisa y declarativa del grafo, y son un requisito estricto para la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link> y los <.localized_link href="/guides/features/selective-testing/generated-xcode-project">tests selectivos</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Proyecto de Gradle {#gradle-project}

Conecta un proyecto de Gradle a la caché remota de Tuist, al análisis de compilaciones y al análisis de tests mediante el plugin `dev.tuist` de Gradle.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Proyecto de Elixir {#elixir-project}

Conecta un proyecto de Elixir al análisis de compilaciones, al análisis de tests, a la detección de tests inestables y al reparto de tests de Tuist mediante el paquete Hex `tuist_ex`.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Proyecto de Rust {#rust-project}

Ejecuta Cargo a través de la CLI de Tuist para informar de las compilaciones y los resultados individuales de los tests, incluidos los doctests, e investigar tests inestables.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Proyecto de Bazel {#bazel-project}

Apunta un espacio de trabajo de Bazel a la caché de la API de ejecución remota de Tuist y al servicio de eventos de compilación para compartir aciertos de caché y análisis con tu equipo y tu CI.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Proyecto de Once {#once-project}

Conecta los scripts cacheables y los grafos de compilación de Once a Tuist para compartir la caché, obtener análisis en tiempo real de compilaciones y tests, usar reparto de tests alojado y vistas previas de aplicaciones.

<.localized_link href="/guides/get-started/once-project">Start with a Once project →</.localized_link>
