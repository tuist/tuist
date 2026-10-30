---
{
  "title": "Rust Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Find slow crates, compare build performance, and inspect Rust compiler warnings and errors in Tuist."
}
---
# Información sobre compilaciones de Rust {#rust-build-insights}

Build Insights te ayuda a identificar qué ralentiza tus compilaciones de Cargo y detectar regresiones antes de que afecten a todo el equipo. Puedes comparar compilaciones locales con CI, ver cómo cambian los tiempos de compilación e inspeccionar las crates compiladas en cada compilación.

> [!IMPORTANT] Requirements
> - Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link> para conectar tu proyecto y autenticarte.

## Reporta tus compilaciones {#report-your-builds}

Ejecuta tus comandos habituales de Cargo a través de Tuist:

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

Si usas mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configura un wrapper de Cargo</.localized_link> para seguir usando los comandos habituales de `cargo`. Tus argumentos, selección de toolchain, salida y código de salida permanecen iguales.

## Identifica qué ralentiza una compilación {#explore-your-builds}

Abre una compilación desde **Compilaciones → Ejecuciones de compilación** en el dashboard. Usa los filtros de fecha, entorno y versión de Rust para comparar compilaciones similares. Las compilaciones y sus contadores de caché también están disponibles a través de `tuist build cargo list` y `tuist build cargo show`, `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, y las `list_cargo_builds` y `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">herramientas MCP</.localized_link>.

En **Resumen**, usa **Tareas del compilador** para encontrar crates lentas. Ordena por **Duración** o **Iniciado después de** (tiempo transcurrido desde que se inició el comando Cargo), o busca por nombre de crate o archivo fuente raíz.

Cada fila representa una invocación de `rustc` para una crate, que puede contener muchos archivos fuente. **Raíz de la crate** identifica su archivo fuente raíz; la duración corresponde a toda la tarea del compilador, no solo a ese archivo. Una crate puede aparecer más de una vez para diferentes targets o configuraciones. Los mensajes del compilador se agrupan en **Advertencias** y **Errores**.

## Interpreta los tiempos {#timing-boundaries}

La duración de la compilación es el tiempo total que tardó el comando Cargo. Las tareas del compilador pueden ejecutarse en paralelo, por lo que sus duraciones no se suman para dar la duración total de la compilación.

Cargo solo compila las crates que necesitan recompilarse. Las crates que ya están actualizadas no aparecerán en la lista del compilador. Con la caché de compilación de Tuist, las tareas restauradas aparecen en las mediciones de caché, no como ejecuciones del compilador.

Tuist no mide los scripts de compilación por separado ni muestra una línea de tiempo de la compilación. Una compilación grande muestra las primeras 500 tareas del compilador, con un aviso si se registraron más.

## Interpreta las mediciones de caché {#cache-measurements}

`tuist cargo` incluye una caché de compilación experimental implementada en la CLI de Tuist. Sigue la <.localized_link href="/guides/features/cache/rust">guía de caché de Rust</.localized_link> para la configuración, lecturas y escrituras remotas a través de Kura, compilaciones compatibles y solución de problemas.

Abre **Caché de Cargo** en la barra lateral del proyecto para rastrear las tasas de aciertos de caché y las mediciones registradas de transferencia, latencia y rendimiento entre compilaciones. Filtra por fecha o entorno, alterna entre tendencias diarias y tasas de aciertos por compilación individual, o abre una compilación reciente para inspeccionar su actividad de caché. Las compilaciones sin mediciones de caché permanecen como no disponibles en lugar de contarse como cero.

Abre la pestaña **Caché** de una compilación para ver los aciertos de tarea, los fallos de tarea, la tasa de aciertos y los bytes descargados y subidos. La pestaña aparece cuando la compilación reporta datos de caché.

- **Tareas cacheables** muestra qué tareas del compilador y de scripts de compilación reutilizaron salidas almacenadas en caché. Busca o filtra las tareas, inspecciona la latencia de lectura/escritura de caché y expande una fila para ver sus salidas.
- **Salidas CAS** muestra las descargas y subidas de artefactos, con sus tamaños, duraciones y rendimiento. El gráfico cuenta las transferencias completadas; los artefactos ya presentes y los intentos fallidos permanecen en la tabla.

**Acierto** significa que se reutilizaron salidas almacenadas en caché. **Fallo** significa que la tarea se compiló en su lugar. Los aciertos no se dividen en locales y remotos; Salidas CAS muestra las operaciones de artefactos registradas.

Si los registros detallados faltan o están incompletos, la página muestra un aviso. El resumen sigue cubriendo toda la compilación. El trabajo estimado del compilador evitado **no es el tiempo de compilación ahorrado**.

> [!WARNING] Experimental compilation cache
> La primera versión almacena en caché solo las bibliotecas hoja del registro con entradas y salidas verificadas. Las crates del workspace, los scripts de compilación, las macros procedurales, las dependencias de otras crates, la compilación incremental, el enlace nativo y los ejecutables se compilan normalmente. Las claves de caché conservan rutas absolutas, por lo que aún no se admite la reutilización entre diferentes rutas de checkout.

### Compilaciones que ejecutan tests {#builds-that-run-tests}

`tuist cargo test` informa la duración de todo el comando, incluidas sus tests. También informa los resultados individuales de las tests, incluidos los doctests, a través de <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>. Los resultados individuales de las tests aparecen bajo **Tests**; la duración del comando aparece en las insights de compilación.

## Otras herramientas del compilador {#other-compiler-tools}

Tuist conserva los wrappers del compilador existentes configurados mediante `RUSTC_WRAPPER`, `CARGO_BUILD_RUSTC_WRAPPER` o la configuración de Cargo, y deja `RUSTC_WORKSPACE_WRAPPER` intacto. Un wrapper global preexistente deshabilita la caché y el observador del compilador de Tuist: Tuist no puede determinar si ese wrapper realmente ejecutó rustc. Los wrappers personalizados del workspace pueden dejar igualmente menos tareas del compilador en el informe.

Tuist encuentra Cargo a través de rustup. Si usas una instalación personalizada, establece `TUIST_CARGO_EXECUTABLE` en su ruta ejecutable. Llamar a Cargo mediante una ruta directa de toolchain omite el wrapper de mise. Un alias de Cargo no puede reemplazar un comando integrado como `build`.

Si usas la opción nocturna `-C` de Cargo, cambia primero al workspace: Tuist reenvía los comandos `-C` pero no recopila sus tiempos de compilación.

## Solución de problemas {#troubleshooting}

Si una compilación no aparece en el dashboard, habilita la salida de depuración para ver por qué no se envió su informe:

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

El reporte no cambia el resultado de tu compilación.
