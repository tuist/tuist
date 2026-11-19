---
{
  "title": "Sharding de tests con Struo",
  "titleTemplate": ":title · Sharding de tests · Funcionalidades · Guías · Tuist",
  "description": "Planifica lotes de tests de Struo a través de Tuist, distribúyelos entre workers de CI e inspecciona una ejecución combinada de tests."
}
---
# Fragmentación de tests con Struo {#struo-test-sharding}

<a id="once-test-sharding"></a>

Cuando tu suite de tests supera la capacidad de una sola máquina, Struo puede pedir a Tuist que distribuya los lotes de tests descubiertos entre los workers de CI. Los workers ejecutan sus asignaciones a través de Struo y Tuist combina sus informes en una única ejecución de tests.

> [!IMPORTANT]
> **Requisitos**
>
> - Completa <.localized_link href="/guides/get-started/struo-project">Primeros pasos con Struo</.localized_link>.
> - Usa [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) o posterior, con `struo query test-plan --shards` y `struo test --shard-plan`.
> - Ten una detección completa para los targets de test seleccionados y el mismo checkout y entorno de test disponible en los workers.

No se requiere ningún wrapper de la CLI de Tuist. Struo usa su proveedor nativo de Tuist y las credenciales correspondientes.

## Descubre tus tests {#discover-your-tests}

Ejecuta los tests seleccionados para establecer la detección antes de planificar:

```bash
struo test MyTests --format json
```

La granularidad de lote disponible depende del runner. Algunos targets de test admiten lotes por archivo o por caso; otros permanecen a nivel de target. Consulta [la guía de testing de Struo](https://struo.run/docs/guide/graph/testing) para conocer las capacidades de detección y agrupación en lotes.

## Crea un plan alojado {#create-a-hosted-plan}

En el trabajo de planificación, usa una referencia compartida por esta ejecución de CI:

```bash
struo query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

La respuesta contiene un ID de plan alojado y los índices reales de los workers:

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

Construye tu matriz de CI a partir de `shards`, en lugar de asumir que contiene cuatro entradas. Un plan vacío devuelve un ID y un array vacíos, por lo que no es necesario iniciar workers. Pasa `--target` para acotar el plan o repite `--changed-path` para usar la selección basada en grafos de Struo.

La referencia toma por defecto `TUIST_SHARD_REFERENCE` o la ejecución de CI detectada. Pásala explícitamente cuando el entorno no tenga un identificador de CI compatible.

## Ejecuta cada fragmento {#execute-each-shard}

Proporciona a cada worker el ID de plan devuelto y su propio índice:

```bash
struo test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

Como alternativa, establece `TUIST_SHARD_PLAN_ID` y `TUIST_SHARD_INDEX`. Los workers descargan el plan vinculado al UUID exacto y ejecutan solo los lotes asignados. Una asignación vacía no ejecuta nada; los resultados faltantes, los procesos fallidos y el trabajo interrumpido no pueden superar la partición.

Esto distribuye un plan de tests, no un archivo precompilado de build de tests. Prepara las fuentes, herramientas y detección necesarias en los workers; la caché compartida puede evitar repetir trabajo de build elegible.

## Reejecuciones y resultados {#reruns-and-results}

Para una reejecución, incrementa `--shard-attempt` o establece `TUIST_SHARD_ATTEMPT`. De lo contrario, Struo usa el intento de ejecución de GitHub y, por defecto, 1. `--shard-report-revision` tiene por defecto 0 y puede incrementarse al corregir un informe dentro del mismo intento. Estos contadores son independientes de los reintentos de un test.

Abre **Tests → Fragmentos** para inspeccionar el plan, el balance y los workers reportados, luego abre la ejecución de tests combinada para ver los resultados individuales. Las unidades de programación de Struo se etiquetan como **Lotes**; los casos conservan sus nombres nativos de target, suite y test.

Consulta <.localized_link href="/guides/features/test-insights/struo">Análisis de tests con Struo</.localized_link> para obtener detalles sobre los informes y las limitaciones de cobertura.
