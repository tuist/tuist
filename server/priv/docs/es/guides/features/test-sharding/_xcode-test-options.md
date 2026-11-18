### Opciones de tests {#test-options}

| Indicador | Variable de entorno | Descripción |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Índice (base cero) del fragmento a ejecutar |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | Identificador exacto del plan de fragmentos emitido por la fase de compilación. Las salidas generadas por el proveedor incluyen este valor automáticamente |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Identificador único del plan de fragmentos (derivado automáticamente en proveedores de CI compatibles) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Ruta al archivo de fragmentos gestionado localmente; Tuist lo extrae en lugar de descargar los productos de prueba desde el almacenamiento remoto |

Tuist descarga el bundle `.xctestproducts` y lo filtra para incluir solo los tests asignados a ese fragmento.
