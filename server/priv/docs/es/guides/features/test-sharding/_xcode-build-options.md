### Opciones de compilación {#build-options}

| Indicador | Variable de entorno | Descripción |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | Número máximo de fragmentos. Se usa con `--shard-max-duration` para limitar la cantidad de fragmentos |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | Número mínimo de fragmentos |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | Número exacto de fragmentos (excluye mutuamente a `--shard-min`/`--shard-max`). Con granularidad por suite, el último fragmento agrupa los restantes |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | Duración máxima objetivo por fragmento en milisegundos |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (predeterminado) distribuye módulos de prueba completos entre fragmentos; `suite` distribuye clases de prueba individuales para un equilibrio más fino |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Identificador único del plan de fragmentación (se deriva automáticamente en proveedores de CI compatibles) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Ruta donde Tuist escribe el archivo optimizado de fragmentos en lugar de subir los productos de prueba al almacenamiento remoto |
