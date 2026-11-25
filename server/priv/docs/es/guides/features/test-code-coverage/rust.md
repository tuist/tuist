---
{
  "title": "Cobertura de código en Rust",
  "titleTemplate": ":title · Cobertura de código · Funcionalidades · Guías · Tuist",
  "description": "Sube la cobertura de líneas de los tests de Cargo de tu proyecto en Rust y hazle seguimiento por archivo, por paquete y por commit."
}
---
# Cobertura de código en Rust {#rust-code-coverage}

La cobertura de código te indica qué líneas de tu código ejecutaron tus tests. Tuist mide la cobertura por línea de cada ejecución de `cargo test` con la cobertura basada en el código fuente de LLVM y consolida las ejecuciones de un commit en una única cifra, para el proyecto, cada paquete y cada archivo. La página **Cobertura de código** del panel muestra estos datos por commit y como tendencia para cada rama.

> [!IMPORTANT]
> **Requisitos**
>
> - Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link>
> - Las herramientas LLVM de tu cadena de herramientas de Rust (`llvm-tools`). Tuist las instala en una cadena de herramientas gestionada por rustup.
> - Tu proyecto en un repositorio Git

## Configuración {#setup}

### Activar la cobertura {#turn-coverage-on}

Añade esto al `Cargo.toml` raíz del workspace:

```toml
[workspace.metadata.tuist.test_insights.coverage]
upload = true
```

Si configuras Tuist en un `tuist.toml` en su lugar, añade `[test_insights.coverage]` con `upload = true` allí.

Luego ejecuta tus tests como de costumbre:

```sh
tuist cargo test --workspace
```

Tuist compila los crates de tu repositorio con `-C instrument-coverage`, ejecuta los tests y sube su cobertura junto con los resultados de test de la ejecución. La salida y el código de salida de tus tests no cambian. Para anular la configuración en una sola ejecución, establece `TUIST_COVERAGE_UPLOAD=1` o `TUIST_COVERAGE_UPLOAD=0`.

La cobertura depende del historial de Git que Tuist sube con cada ejecución que la recopila, lo que sitúa el commit en su rama. Una ejecución fuera de un repositorio Git sube sus resultados de test pero no la cobertura. Una ejecución desde una copia de trabajo de un commit en lugar de una rama no tiene rama y no sitúa su commit en ninguna; en un sistema de CI que Tuist no reconoce, nombra la rama con `TUIST_GIT_BRANCH`, como describe <.localized_link href="/guides/features/test-insights/rust#continuous-integration">integración continua</.localized_link>.

### Ejecuciones fragmentadas {#sharded-runs}

Cuando <.localized_link href="/guides/features/test-sharding/rust">fragmentas tus tests</.localized_link>, cada fragmento que se ejecuta con la cobertura activada informa de la cobertura de sus propios targets, y Tuist fusiona los fragmentos de una ejecución en una única cifra. Un fragmento ejecuta parte de la suite a propósito, por lo que no hace que la cobertura del commit esté incompleta.

### Completar cada commit en CI {#complete-each-commit}

La cobertura de un commit suele proceder de varios trabajos: uno por fragmento o por conjunto de funcionalidades. Tuist no puede saber cuándo ha informado el último de ellos, así que debes indicárselo. Una vez que haya terminado cada trabajo de test para un commit, ejecuta esto en un trabajo que dependa de todos ellos:

```sh
tuist coverage complete
```

El comando lee el commit desde el `HEAD` de la copia de trabajo, el commit sobre el que se ejecutaron tus tests; pasa `--commit <sha>` para indicar otro distinto. Hasta que un commit esté completo, su cobertura aparece como **En progreso** y queda fuera de la tendencia de su rama.

## Cómo funciona {#how-it-works}

### Qué mide Tuist {#what-tuist-measures}

- **Paquetes.** Cada paquete de Cargo es un target en el panel, con su propia cobertura.
- **Solo código de producto.** Los tests de integración, benchmarks y ejemplos (los directorios `tests/`, `benches/` y `examples/`, y los targets de esos tipos) son código de test. Tuist los almacena pero los excluye de todas las cifras. Los tests unitarios en un módulo `#[cfg(test)]` forman parte de su archivo fuente, por lo que sus líneas cuentan con él, como en `cargo llvm-cov`.
- **Funciones.** Cada línea pertenece a la función que comienza más cerca por encima de ella. Una función genérica cuenta una vez, independientemente de cuántos tipos se hayan instanciado con ella.
- Los **doctests** se ejecutan como de costumbre pero no se miden.

Tuist también registra qué código ejecutó cada binario de test, para la selección de tests basada en cobertura posteriormente. `cargo test` ejecuta los tests de un binario en un único proceso, por lo que ese registro pertenece al binario en su conjunto, no a sus tests individuales.

### Tests omitidos {#skipped-tests}

Cuando los argumentos propios de una ejecución excluyen tests, como un filtro por nombre de test, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` o `--test`, la cobertura del commit es **Incompleta**, a menos que también se haya ejecutado otra ejecución del commit que no haya excluido nada. Un fallo que detiene `cargo test` antes de que se ejecute cada binario de test tiene el mismo efecto. Añade `--no-fail-fast` para seguir ejecutando los binarios restantes.

Algunos tests se excluyen a propósito y no hacen que un commit esté incompleto:

- **Tests que <.localized_link href="/guides/features/test-insights/flaky-tests/rust">cuarentena</.localized_link> omite.** Se excluyen como si se hubieran eliminado, por lo que las líneas que solo ellos cubrieron cuentan como no cubiertas.
- **Los targets de los otros fragmentos**, cuando fragmentas tus tests.
- **Tests ignorados** (`#[ignore]`), que no se ejecutan por defecto.

### Cambios sin confirmar {#uncommitted-changes}

Una ejecución desde una copia de trabajo cuyos archivos rastreados tienen cambios sin confirmar midió código que no es el del commit, por lo que su cobertura no cuenta para el commit. La ejecución emite una advertencia y enumera los archivos cambiados. Los archivos que tu trabajo de CI escribe junto a las fuentes, como salidas de compilación o informes de cobertura, no cuentan como cambios mientras Git no los rastree. Cuando solo tales ejecuciones midieron un commit, su cobertura es **Incompleta** y `tuist coverage complete` indica el motivo.

### Commits completos e incompletos {#commit-status}

Cada commit en el panel tiene un estado:

| Estado | Significado |
| --- | --- |
| En progreso | Las ejecuciones han informado de cobertura, pero `tuist coverage complete` aún no se ha ejecutado para el commit. |
| Completo | Se ejecutaron todos los tests de las ejecuciones del commit, o se omitieron a propósito. |
| Incompleto | No se pudo determinar parte de la cobertura, por lo que la cifra es un límite inferior. |
| No medido | Ninguna ejecución informó de cobertura para el commit. |

La tendencia de una rama solo incluye commits completos.

## Impacto en el rendimiento {#performance-impact}

El código instrumentado se ejecuta un poco más lento. Tuist solo instrumenta los crates de tu repositorio: las dependencias se compilan exactamente igual que en tus compilaciones habituales y siguen obteniéndose de la caché. Tuist mantiene ambas variantes de tus propios crates en el directorio target, por lo que cambiar entre ejecuciones con y sin cobertura no los recompila a menos que su código haya cambiado.

## Limitaciones {#limitations}

- **`rustc-wrapper` personalizado con `rustflags` específicos del target.** Cuando tu proyecto configura su propio `rustc-wrapper`, Tuist añade `-C instrument-coverage` a `build.rustflags` de Cargo en su lugar. Una entrada `target.<triple>.rustflags` en un archivo de configuración de Cargo las reemplaza, así que añade la bandera allí tú mismo. Una ejecución cuyos tests no generaron cobertura lo indica.
- **Runners de target configurados.** Tuist inicia los binarios de test a través de un runner propio. Un `target.<triple>.runner` en un archivo de configuración de Cargo toma su lugar: la cobertura de la ejecución sigue subiéndose, pero Tuist no puede saber qué binario de test ejecutó qué. Un runner establecido mediante la variable de entorno `CARGO_TARGET_<TRIPLE>_RUNNER` sigue funcionando.
- **Sin cobertura desde pull requests de forks.** La cobertura solo se sube mediante ejecuciones que se autentican con Tuist, y la CI suele retener los secretos y tokens de identidad de las pull requests abiertas desde forks.

## Consulta de cobertura {#querying}

La página **Cobertura de código** del panel muestra la cifra de cada commit, sus paquetes y sus archivos, con las funciones que contiene cada archivo. Los mismos datos están disponibles para los agentes a través del <.localized_link href="/guides/features/agentic-coding/mcp">servidor de Model Context Protocol</.localized_link>.
