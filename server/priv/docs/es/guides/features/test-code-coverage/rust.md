---
{
  "title": "Cobertura de código en Rust",
  "titleTemplate": ":title · Cobertura de código · Funcionalidades · Guías · Tuist",
  "description": "Sube la cobertura por líneas de los tests de Cargo de tu proyecto en Rust y haz seguimiento por archivo, por paquete y por commit."
}
---
# Cobertura de código en Rust {#rust-code-coverage}

La cobertura de código te indica qué líneas de tu código ejecutaron tus tests. Tuist mide la cobertura por línea de cada ejecución de `cargo test` con la cobertura basada en el código fuente de LLVM y consolida las ejecuciones de un commit en una única cifra, para el proyecto, cada paquete y cada archivo. La página **Cobertura de código** del panel la muestra por commit y como tendencia para cada rama.

> [!IMPORTANT]
> **Requisitos**
>
> - Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link>
> - Las herramientas LLVM de tu cadena de herramientas de Rust (`llvm-tools`). Tuist las instala en una cadena de herramientas gestionada por rustup.
> - Tu proyecto en un repositorio Git

## Configuración {#setup}

### Activar la cobertura {#turn-coverage-on}

Añade esto al `tuist.toml` en la raíz de tu repositorio:

```toml
[test_insights.coverage]
upload = true
```

Luego ejecuta tus tests como de costumbre:

```sh
tuist cargo test --workspace
```

Tuist compila los crates de tu repositorio con `-C instrument-coverage`, ejecuta los tests y sube su cobertura junto con los resultados de los tests de la ejecución. La salida y el código de salida de tus tests no cambian. Para anular la configuración en una sola ejecución, establece `TUIST_COVERAGE_UPLOAD=1` o `TUIST_COVERAGE_UPLOAD=0` .

La cobertura depende del historial de Git que Tuist sube con cada ejecución que la recopila, lo que sitúa el commit en su rama. Una ejecución fuera de un repositorio Git sube sus resultados de tests, pero no la cobertura.

### Ejecuciones fragmentadas {#sharded-runs}

Cuando <.localized_link href="/guides/features/test-sharding/rust">fragmentas tus tests</.localized_link>, cada fragmento que se ejecuta con la cobertura activada informa de la cobertura de sus propios objetivos, y Tuist fusiona los fragmentos de una ejecución en una única cifra. Un fragmento ejecuta parte del conjunto de tests a propósito, por lo que no hace que la cobertura del commit sea incompleta.

### Completa cada commit en CI {#complete-each-commit}

La cobertura de un commit suele provenir de varios trabajos: uno por fragmento o por conjunto de funcionalidades. Tuist no puede saber cuándo ha informado el último de ellos, así que debes indicárselo. Una vez que haya terminado cada trabajo de test para un commit, ejecuta esto en un trabajo que dependa de todos ellos:

```sh
tuist cargo coverage-complete
```

El comando lee el commit desde el checkout, o el que tu proveedor de CI informa en una pull request; pasa `--commit <sha>` para indicar otro. Hasta que un commit esté completo, su cobertura aparece como **En progreso** y queda fuera de la tendencia de su rama.

## Cómo funciona {#how-it-works}

### Qué mide Tuist {#what-tuist-measures}

- **Paquetes.** Cada paquete de Cargo es un objetivo en el panel, con su propia cobertura.
- **Solo código de producto.** Los tests de integración, los benchmarks y los ejemplos (los directorios `tests/`, `benches/` y `examples/`, y los objetivos de esos tipos) son código de test. Tuist los almacena, pero los excluye de todas las cifras. Los tests unitarios en un módulo `#[cfg(test)]` forman parte de su archivo fuente, por lo que sus líneas cuentan con él, como en `cargo llvm-cov` .
- **Funciones.** Cada línea pertenece a la función que comienza más cerca por encima de ella. Una función genérica cuenta una vez, independientemente de cuántos tipos se hayan instanciado con ella.
- Los **doctests** se ejecutan como de costumbre, pero no se miden.

Tuist también registra qué código ejecutó cada binario de test, para la selección de tests basada en la cobertura más adelante. `cargo test` ejecuta los tests de un binario en un solo proceso, por lo que ese registro pertenece al binario en su conjunto, no a sus tests individuales.

### Tests omitidos {#skipped-tests}

Cuando los propios argumentos de una ejecución dejan tests fuera, como un filtro por nombre de test, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` o `--test`, la cobertura del commit es **Incompleta**, a menos que también se haya ejecutado otra ejecución del commit que no haya dejado nada fuera. Un fallo que detiene `cargo test` antes de que se ejecute cada binario de test tiene el mismo efecto. Añade `--no-fail-fast` para seguir ejecutando los binarios restantes.

Algunos tests se omiten a propósito y no hacen que un commit sea incompleto:

- **Tests que <.localized_link href="/guides/features/test-insights/flaky-tests/rust">la cuarentena</.localized_link> omite.** Se dejan fuera como si se hubieran eliminado, por lo que las líneas que solo ellos cubrieron se cuentan como no cubiertas.
- **Los objetivos de los otros fragmentos**, cuando fragmentas tus tests.
- **Tests ignorados** (`#[ignore]`), que no se ejecutan por defecto.

### Commits completos e incompletos {#commit-status}

Cada commit en el panel tiene un estado:

| Estado | Significado |
| --- | --- |
| En progreso | Las ejecuciones han informado de la cobertura, pero `tuist cargo coverage-complete` aún no se ha ejecutado para el commit. |
| Completo | Se ejecutó cada test de las ejecuciones del commit, o se dejó fuera a propósito. |
| Incompleto | No se pudo determinar parte de la cobertura, por lo que la cifra es un límite inferior. |
| No medido | Ninguna ejecución informó de la cobertura para el commit. |

La tendencia de una rama solo incluye commits completos.

## Impacto en el rendimiento {#performance-impact}

El código instrumentado se ejecuta un poco más lento. Tuist instrumenta solo los crates de tu repositorio: las dependencias se compilan exactamente igual que en tus compilaciones habituales y siguen obteniéndose de la caché. Tuist mantiene ambas variantes de tus propios crates en el directorio de destino, por lo que cambiar entre ejecuciones con y sin cobertura no los recompila a menos que su código haya cambiado.

## Limitaciones {#limitations}

- **`rustc-wrapper` personalizado con `rustflags` específicos del objetivo.** Cuando tu proyecto configura su propio `rustc-wrapper`, Tuist añade `-C instrument-coverage` a `build.rustflags` de Cargo en su lugar. Una entrada `target.<triple>.rustflags` en un archivo de configuración de Cargo las reemplaza, así que añade la bandera allí tú mismo. Una ejecución cuyos tests no generaron cobertura lo indica.
- **Ejecutores de objetivo configurados.** Tuist inicia los binarios de test a través de su propio ejecutor. Un `target.<triple>.runner` en un archivo de configuración de Cargo toma su lugar: la cobertura de la ejecución sigue subiéndose, pero Tuist no puede determinar qué binario de test ejecutó qué. Un ejecutor establecido mediante la variable de entorno `CARGO_TARGET_<TRIPLE>_RUNNER` sigue funcionando.
- **Sin cobertura desde pull requests de forks.** La cobertura solo se sube mediante ejecuciones que se autentican con Tuist, y la CI suele retener los secretos y tokens de identidad de las pull requests abiertas desde forks.

## Consulta de cobertura {#querying}

La página **Cobertura de código** del panel muestra la cifra de cada commit, sus paquetes y sus archivos, con las funciones que contiene cada archivo. Los mismos datos están disponibles para los agentes a través del <.localized_link href="/guides/features/agentic-coding/mcp">servidor Model Context Protocol</.localized_link>.
