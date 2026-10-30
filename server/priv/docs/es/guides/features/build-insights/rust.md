---
{
  "title": "Análisis de compilaciones de Rust",
  "titleTemplate": ":title · Análisis de compilaciones · Funcionalidades · Guías · Tuist",
  "description": "Encuentra crates lentos, compara el rendimiento de la compilación e inspecciona advertencias y errores del compilador de Rust en Tuist."
}
---
# Análisis de compilaciones de Rust {#rust-build-insights}

Build Insights te ayuda a identificar qué ralentiza tus compilaciones de Cargo y a detectar regresiones antes de que afecten a todo el equipo. Puedes comparar compilaciones locales con las de CI, ver cómo cambian los tiempos de compilación e inspeccionar los crates compilados en cada compilación.

> [!IMPORTANT] Requirements
> - Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link> para conectar tu proyecto y autenticarte.

## Informa de tus compilaciones {#report-your-builds}

Ejecuta tus comandos habituales de Cargo a través de Tuist:

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

Si usas mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configura un envoltorio de Cargo</.localized_link> para seguir usando los comandos habituales de `cargo`. Tus argumentos, selección de toolchain, salida y código de salida se mantienen iguales.

## Identifica qué ralentiza una compilación {#explore-your-builds}

Abre una compilación desde **Compilaciones → Ejecuciones de compilación** en el dashboard. Usa los filtros de fecha, entorno y versión de Rust para comparar compilaciones similares. Las compilaciones y sus contadores de caché también están disponibles a través de `tuist build cargo list` y `tuist build cargo show`, `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, y las herramientas `list_cargo_builds` y `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>.

En **Resumen**, usa **Tareas del compilador** para encontrar crates lentos. Ordena por **Duración** o **Iniciado después de** (tiempo transcurrido desde que se inició el comando de Cargo), o busca por nombre de crate o archivo fuente raíz.

Cada fila representa una invocación de `rustc` para un crate, que puede contener muchos archivos fuente. **Raíz del crate** identifica su archivo fuente raíz; la duración corresponde a toda la tarea del compilador, no solo a ese archivo. Un crate puede aparecer más de una vez para diferentes targets o configuraciones. Los mensajes del compilador se agrupan en **Advertencias** y **Errores**.

## Interpreta los tiempos {#timing-boundaries}

La duración de la compilación es el tiempo total que tardó el comando de Cargo. Las tareas del compilador pueden ejecutarse en paralelo, por lo que sus duraciones no se suman para igualar la duración de la compilación.

Cargo solo compila los crates que necesitan recompilarse. Los crates que ya están actualizados no aparecen en la lista del compilador. Con la caché de compilación de Tuist, las tareas restauradas aparecen en las mediciones de caché, no como ejecuciones del compilador.

Tuist no mide los scripts de compilación por separado ni muestra una línea de tiempo de la compilación. Una compilación grande muestra las primeras 500 tareas del compilador, con un aviso si se registraron más.

## Interpreta las mediciones de caché {#cache-measurements}

`tuist cargo` incluye una caché de compilación experimental implementada en la CLI de Tuist. Sigue la <.localized_link href="/guides/features/cache/rust">guía de caché de Rust</.localized_link> para la configuración, lecturas y escrituras remotas a través de Kura, compilaciones admitidas y solución de problemas.

Abre **Caché de Cargo** en la barra lateral del proyecto para rastrear las tasas de aciertos de caché y las mediciones registradas de transferencia, latencia y rendimiento entre compilaciones. Filtra por fecha o entorno, alterna entre tendencias diarias y tasas de aciertos por compilación individual, o abre una compilación reciente para inspeccionar su actividad de caché. Las compilaciones sin mediciones de caché permanecen como no disponibles en lugar de contarse como cero.

Abre la pestaña **Caché** de una compilación para ver los aciertos de tarea, los fallos de tarea, la tasa de aciertos y los bytes descargados y subidos. La pestaña aparece cuando la compilación informa datos de caché.

- **Tareas cacheables** muestra qué tareas del compilador y de los scripts de compilación reutilizaron salidas almacenadas en caché. Busca o filtra las tareas, inspecciona la latencia de lectura/escritura de la caché y expande una fila para ver sus salidas.
- **Salidas CAS** muestra las descargas y subidas de artefactos, con sus tamaños, duraciones y rendimiento. El gráfico cuenta las transferencias completadas; los artefactos ya presentes y los intentos fallidos permanecen en la tabla.

**Acierto** significa que se reutilizaron salidas almacenadas en caché. **Fallo** significa que la tarea se compiló en su lugar. Los aciertos no se dividen en locales y remotos; Salidas CAS muestra las operaciones de artefactos registradas.

Si faltan registros detallados o están incompletos, la página muestra un aviso. El resumen sigue cubriendo toda la compilación. El trabajo estimado del compilador evitado **no es el tiempo de compilación ahorrado**.

> [!WARNING] Experimental compilation cache
> La primera versión almacena en caché solo las bibliotecas hoja del registro con entradas y salidas verificadas. Los crates del workspace, los scripts de compilación, las macros procedurales, las dependencias de otros crates, la compilación incremental, el enlazado nativo y los ejecutables se compilan normalmente. Las claves de caché conservan rutas absolutas, por lo que la reutilización entre diferentes rutas de checkout aún no es compatible.

### Compilaciones que ejecutan tests {#builds-that-run-tests}

`tuist cargo test` informa la duración de todo el comando, incluidos sus tests. También informa los resultados individuales de los tests, incluidos los doctests, a través de <.localized_link href="/guides/features/test-insights/rust">Análisis de tests de Rust</.localized_link>. Los resultados individuales de los tests aparecen en **Tests**; la duración del comando aparece en los análisis de compilaciones.

## Otras herramientas del compilador {#other-compiler-tools}

Tuist conserva los wrappers del compilador existentes configurados a través de `RUSTC_WRAPPER`, `CARGO_BUILD_RUSTC_WRAPPER` o la configuración de Cargo, y deja `RUSTC_WORKSPACE_WRAPPER` intacto. Un wrapper global preexistente deshabilita la caché y el observador del compilador de Tuist: Tuist no puede determinar si ese wrapper realmente ejecutó rustc. Los wrappers personalizados del workspace pueden dejar igualmente fewer tareas del compilador en el informe.

Tuist encuentra Cargo a través de rustup. Si usas una instalación personalizada, establece `TUIST_CARGO_EXECUTABLE` en su ruta ejecutable. Llamar a Cargo mediante una ruta directa de la toolchain omite el wrapper de mise. Un alias de Cargo no puede reemplazar un comando integrado como `build`.

Si usas la opción nightly `-C` de Cargo, cambia primero al directorio del workspace: Tuist reenvía los comandos `-C` pero no recopila sus tiempos de compilación.

## Solución de problemas {#troubleshooting}

Si una compilación no aparece en el dashboard, habilita la salida de depuración para ver por qué no se envió su informe:

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

El informe no cambia el resultado de tu compilación.
