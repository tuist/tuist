---
{
  "title": "Fragmentación de tests en Rust",
  "titleTemplate": ":title · Fragmentación de tests · Funcionalidades · Guías · Tuist",
  "description": "Distribuye los targets de pruebas de Cargo entre los workers de CI usando las duraciones históricas de los tests."
}
---
# Fragmentación de tests en Rust {#rust-test-sharding}

Tuist distribuye los objetivos de test de Cargo entre los workers de CI usando las duraciones históricas de cada objetivo. Los objetivos de tests unitarios, los de tests de integración y los doctests de cada biblioteca son módulos separados. Los tests dentro de un mismo objetivo se mantienen juntos.

> [!IMPORTANT]
> **Requisitos**
>
> - Configura <.localized_link href="/guides/features/test-insights/rust">Análisis de tests de Rust</.localized_link> y autentica la CLI en el job de planificación y en los workers.
> - Selecciona un único paquete usando `-p <package>` en un workspace. No se admite la fragmentación entre varios paquetes.
> - Usa la misma revisión, toolchain de Rust, selección de paquetes, features y filtros de tests en cada job.

## Crear un plan {#create-a-plan}

Añade un recuento de shards a `--no-run` para compilar y enumerar los objetivos sin ejecutar los tests:

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

El comando imprime JSON que contiene `shard_plan_id` y un array `shards` con índice cero. En GitHub Actions, también escribe `shard-plan-id` y `shards` en `GITHUB_OUTPUT`. Sin una referencia explícita, Tuist deriva una del entorno de CI compatible.

| Opción | Descripción |
| --- | --- |
| `--shard-max N` | Número máximo de shards |
| `--shard-min N` | Número mínimo de shards |
| `--shard-total N` | Recuento exacto, hasta el número de objetivos disponibles |
| `--shard-max-duration N` | Duración máxima objetivo por shard en milisegundos |

Usa `--shard-total` solo o combina `--shard-min` y `--shard-max`. Sin duraciones históricas, el planificador usa estimaciones predeterminadas para los objetivos. Un `--no-run` normal sin opciones de shard sigue siendo un comando de solo compilación.

## Ejecutar cada shard {#execute-each-shard}

Establece el ID del plan y el índice del shard en cada worker y luego usa los mismos argumentos de test de Cargo:

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

Como alternativa, establece `TUIST_SHARD_REFERENCE` con la referencia del job de planificación en lugar de pasar el ID del plan. Tuist obtiene la asignación y pide a Cargo que ejecute solo esos objetivos. Las asignaciones no válidas o incompatibles hacen fallar el comando en lugar de ejecutar todos los tests. Las asignaciones vacías no ejecutan ningún test. Los resultados de los workers se vinculan al plan en Análisis de tests, y la <.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantining">cuarentena</.localized_link> se aplica dentro de cada shard.

## Límites {#limits}

Se trata de fragmentación a nivel de objetivo, no de distribución con una única compilación. Cada worker necesita el checkout del código fuente y compila sus propios objetivos; la <.localized_link href="/guides/features/cache/rust">caché de compilación de Cargo</.localized_link> puede reutilizar los artefactos de compilación elegibles. Tuist no sube los ejecutables de los tests ni requiere otro runner de tests de Rust.

La fragmentación requiere un único paquete seleccionado. Restringir un comando multi-paquete puede cambiar las features unificadas de las dependencias de Cargo, por lo que Tuist lo rechaza en lugar de ejecutar tests con un grafo de features distinto. Planifica cada paquete por separado hasta que se admita la fragmentación multi-paquete.

La fragmentación requiere harnesses estándar de libtest y la captura de la salida predeterminada. Se rechazan los comandos silenciosos, verbosos, con formato alternativo, con salida no capturada y con harness personalizado. Si Cargo no puede identificar unívocamente un objetivo, selecciona un paquete exacto del workspace con `-p <package>`. Los paquetes de dependencias, los selectores calificados por versión, los patrones glob de nombre de paquete/objetivo y la opción nocturna `-C` de Cargo no son compatibles con la fragmentación. Mantén la selección de tests idéntica entre la planificación y la ejecución.
