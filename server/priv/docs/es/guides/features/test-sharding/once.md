---
{
  "title": "Test Sharding con Once",
  "titleTemplate": ":title · Test Sharding · Funcionalidades · Guías · Tuist",
  "description": "Planifica lotes de tests con Once a través de Tuist, distribúyelos entre workers de CI e inspecciona una ejecución de tests combinada."
}
---
# Particionamiento de tests con Once {#once-test-sharding}

Cuando tu suite de tests supera la capacidad de una sola máquina, Once puede pedir a Tuist que distribuya los lotes de tests descubiertos entre los workers de CI. Los workers ejecutan sus asignaciones a través de Once y Tuist combina sus informes en una única ejecución de tests.

> [!IMPORTANT]
> **Requisitos**
>
> - Completa <.localized_link href="/guides/get-started/once-project">Primeros pasos con Once</.localized_link>.
> - Usa una versión de Once que exponga `once query test-plan --shards` y `once test --shard-plan`. Once 0.71.0 solo admite planes portables, no este flujo de trabajo alojado.
> - Asegúrate de tener un descubrimiento completo para los targets de test seleccionados y de que el mismo checkout y entorno de test estén disponibles en los workers.

No se requiere ningún wrapper del CLI de Tuist. Once usa su proveedor nativo de Tuist y sus credenciales.

## Descubre tus tests {#discover-your-tests}

Ejecuta los tests seleccionados para establecer el descubrimiento antes de planificar:

```bash
once test MyTests --format json
```

La granularidad de lote disponible depende del runner. Algunos targets de test admiten lotes por archivo o por caso; otros permanecen a nivel de target. Consulta [la guía de testing de Once](https://buildonce.dev/docs/guide/graph/testing) para conocer las capacidades de descubrimiento y agrupación en lotes.

## Crea un plan alojado {#create-a-hosted-plan}

En el trabajo de planificación, usa una referencia compartida por esta ejecución de CI:

```bash
once query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

La respuesta contiene un ID de plan alojado y los índices reales de los workers:

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

Construye tu matriz de CI a partir de `shards`, en lugar de asumir que contiene cuatro entradas. Un plan vacío devuelve un ID y un array vacíos, por lo que no es necesario iniciar workers. Pasa `--target` para acotar el plan o repite `--changed-path` para usar la selección basada en grafos de Once.

La referencia toma por defecto `TUIST_SHARD_REFERENCE` o la ejecución de CI detectada. Pásala explícitamente cuando el entorno no tenga un identificador de CI compatible.

## Ejecuta cada shard {#execute-each-shard}

Proporciona a cada worker el ID del plan devuelto y su propio índice:

```bash
once test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

Como alternativa, establece `TUIST_SHARD_PLAN_ID` y `TUIST_SHARD_INDEX`. Los workers descargan el plan vinculado al UUID exacto y ejecutan solo los lotes asignados. Una asignación vacía no ejecuta nada; los resultados faltantes, los procesos fallidos y el trabajo interrumpido no pueden superar la partición.

Esto distribuye un plan de test, no un archivo de build de test precompilado. Prepara las fuentes, herramientas y el descubrimiento necesarios en los workers; la caché compartida puede evitar repetir trabajo de build elegible.

## Reejecuciones y resultados {#reruns-and-results}

Para una reejecución, incrementa `--shard-attempt` o establece `TUIST_SHARD_ATTEMPT`. De lo contrario, Once usa el intento de ejecución de GitHub y, por defecto, 1. `--shard-report-revision` tiene por defecto 0 y puede incrementarse al corregir un informe dentro del mismo intento. Estos contadores son independientes de los reintentos de un test.

Abre **Tests → Shards** para inspeccionar el plan, el balance y los workers reportados, luego abre la ejecución de tests combinada para ver los resultados individuales. Las unidades de programación de Once se etiquetan como **Lotes**; los casos conservan sus nombres nativos de target, suite y test.

Consulta <.localized_link href="/guides/features/test-insights/once">Análisis de tests con Once</.localized_link> para obtener detalles sobre los informes y las limitaciones de cobertura.
