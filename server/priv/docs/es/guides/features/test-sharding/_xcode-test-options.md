### Opciones de test {#test-options}

| Flag | Variable de entorno | Descripción |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Índice de base cero del shard a ejecutar |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | Identificador exacto del plan de shard emitido por la fase de compilación. Las salidas generadas por el proveedor incluyen este valor automáticamente |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Identificador único para el plan de shard (se deriva automáticamente en proveedores de CI compatibles) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Ruta a un archivo de shard gestionado localmente; Tuist lo extrae en lugar de descargar los productos de test desde el almacenamiento remoto |

Tuist descarga el bundle `.xctestproducts` y lo filtra para incluir solo los tests asignados a ese shard.
