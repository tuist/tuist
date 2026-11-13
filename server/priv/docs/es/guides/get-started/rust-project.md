---
{
  "title": "Proyecto Rust",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Conecta tu proyecto Rust a Tuist para realizar seguimiento de compilaciones y tests, incluidos los doctests, y encontrar tests inestables."
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

Instala la <.localized_link href="/guides/install-tuist">CLI de Tuist</.localized_link> y Rust. Crea un proyecto en el panel con **Cargo (Rust)** como sistema de compilación. Añade un `tuist.toml` en la raíz de tu repositorio:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Inicia sesión con `tuist auth login`, luego ejecuta tus comandos habituales de Cargo a través de Tuist. En CI, autentícate con la identidad OIDC de tu proveedor de CI o establece `TUIST_TOKEN` en un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link>. También puedes establecer `TUIST_PROJECT` en lugar de añadir un archivo de configuración, y `TUIST_URL` si usas un servidor autoalojado.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Usa los mismos argumentos que normalmente pasas a Cargo, incluyendo características, toolchains y filtros de tests. Cargo mantiene su salida y código de salida habituales, incluso si Tuist no puede subir un informe.

## Sigue escribiendo Cargo

Con los [wrappers de comandos de mise](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) activados, añade esto a `mise.toml`:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Ejecuta `mise reshim` después de añadir el wrapper. Luego puedes usar `cargo build`, `cargo check` y `cargo test` como de costumbre. Mise los ejecuta a través de Tuist por ti.

> [!TIP] Coding agents
> Esto es útil al trabajar con agentes de programación: pueden seguir ejecutando `cargo build` y `cargo test` sin que haya que recordarles añadir el prefijo `tuist`.

## Caché de compilación

`tuist cargo build` almacena en caché automáticamente las compilaciones elegibles, las dependencias y las ejecuciones de scripts de compilación, localmente y a través de la caché remota de Kura. No se necesita ninguna herramienta adicional ni configuración de caché. La caché es experimental, está validada en Macs con Apple silicon y aún no cubre todas las compilaciones. Consulta la <.localized_link href="/guides/features/cache/rust">caché de Rust</.localized_link> para ver las compilaciones admitidas, la autenticación y cómo verificar la reutilización.

## Análisis de compilaciones

Abre **Compilaciones** en el panel para ver cuánto tardan tus compilaciones y comparar las compilaciones locales con CI. Selecciona una compilación para encontrar los crates que más tardaron en compilarse e inspeccionar sus advertencias y errores.

Los tiempos del compilador corresponden a crates, no a archivos fuente individuales. Consulta los <.localized_link href="/guides/features/build-insights/rust">Análisis de compilaciones de Rust</.localized_link> para obtener más información sobre cómo leer un informe de compilación.

## Análisis de tests

Ejecuta tus tests como de costumbre:

```sh
tuist cargo test --workspace
```

Abre **Tests** en el panel para ver los tests aprobados, fallidos e ignorados, incluidos los doctests. Cargo informa de las duraciones de las suites, pero libtest estable no expone los tiempos por test.

Para ejecutar solo doctests:

```sh
tuist cargo test --doc
```

Lee más en <.localized_link href="/guides/features/test-insights/rust">Análisis de tests de Rust</.localized_link> y <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Tests inestables de Rust</.localized_link>.
