---
{
  "title": "Rust project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect your Rust project to Tuist to track builds and tests, including doctests, and find flaky tests."
}
---
# Proyecto Rust {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## Requisitos previos

- Un proyecto Rust compilado con Cargo.
- La CLI de Tuist y una cuenta de Tuist.

Tuist funciona con tu proyecto Cargo existente. No necesitas añadir una dependencia de Rust ni cambiar cómo se compila tu proyecto.

## Conectar el proyecto

Instala la <.localized_link href="/guides/install-tuist">CLI de Tuist</.localized_link> y Rust. Crea un proyecto en el dashboard con **Cargo (Rust)** como su sistema de compilación. Añade un `tuist.toml` en la raíz de tu repositorio:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Inicia sesión con `tuist auth login`, luego ejecuta tus comandos habituales de Cargo a través de Tuist. En CI, establece `TUIST_TOKEN` con un token de proyecto. También puedes establecer `TUIST_PROJECT` en lugar de añadir un archivo de configuración, y `TUIST_URL` si usas un servidor autoalojado.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Usa los mismos argumentos que normalmente pasas a Cargo, incluyendo funcionalidades, toolchains y filtros de tests. Cargo mantiene su salida y código de salida habituales, incluso si Tuist no puede subir un informe.

## Sigue escribiendo Cargo

Con [los envoltorios de comandos de mise](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) habilitados, añade esto a `mise.toml`:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Ejecuta `mise reshim` después de añadir el envoltorio. Luego puedes usar `cargo build`, `cargo check` y `cargo test` como de costumbre. Mise los ejecuta a través de Tuist por ti.

> [!TIP] Coding agents
> Esto es útil al trabajar con agentes de codificación: pueden seguir ejecutando `cargo build` y `cargo test` sin necesidad de recordarles añadir el prefijo `tuist`.

## Caché de compilación

`tuist cargo build` almacena en caché automáticamente las bibliotecas hoja elegibles del registro, localmente y a través de la caché remota de Kura. No se necesita ninguna herramienta o configuración de caché adicional. La caché es experimental y aún no cubre todas las compilaciones ni la reutilización entre diferentes rutas de checkout. Consulta <.localized_link href="/guides/features/cache/rust">caché de Rust</.localized_link> para ver las compilaciones compatibles, la autenticación y cómo verificar la reutilización.

## Información de compilación

Abre **Compilaciones** en el dashboard para ver cuánto tardan tus compilaciones y comparar las compilaciones locales con CI. Selecciona una compilación para encontrar los crates que más tardaron en compilarse e inspeccionar sus advertencias y errores.

Los tiempos del compilador son para crates, no para archivos fuente individuales. Consulta <.localized_link href="/guides/features/build-insights/rust">Información de compilación de Rust</.localized_link> para obtener más detalles sobre cómo leer un informe de compilación.

## Información de tests

Ejecuta tus tests como de costumbre:

```sh
tuist cargo test --workspace
```

Abre **Tests** en el dashboard para ver los tests aprobados, fallidos e ignorados, incluidos los doctests. Cargo informa de las duraciones de la suite, pero libtest estable no expone los tiempos por test.

Para ejecutar solo doctests:

```sh
tuist cargo test --doc
```

Lee más en <.localized_link href="/guides/features/test-insights/rust">Información de tests de Rust</.localized_link> y <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Tests inestables de Rust</.localized_link>.
