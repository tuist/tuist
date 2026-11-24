---
{
  "title": "Once Test Insights",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Inspecciona suites de tests, resultados individuales, fallos y duraciones en el panel de control de Tuist."
}
---
# Análisis de tests con Once {#once-test-insights}

Once envía los resultados de los tests a Tuist para que puedas seguir tu suite en ejecuciones locales y de CI, investigar fallos y encontrar tests lentos sin tener que recopilar informes de cada worker.

> [!IMPORTANT]
> **Requisitos**
>
> - Completa <.localized_link href="/guides/get-started/once-project">Primeros pasos con Once</.localized_link>.
> - Usa targets de test que informen resultados estructurados. El nivel de detalle disponible depende del tipo de target y del runner de tests.

## Informa tus ejecuciones de tests {#report-your-test-runs}

Ejecuta toda la suite o selecciona un target:

```bash
once test
once test MyTests
```

Once transmite eventos nativos de tests y publica los resultados completados en el modelo compartido de tests de Tuist. **Tests** y **Ejecuciones de tests** muestran las ejecuciones; los casos individuales también tienen un historial compartido. Una <.localized_link href="/guides/features/test-sharding/once">ejecución fragmentada alojada</.localized_link> publica un informe por worker en una ejecución combinada en lugar de volver a contabilizar su flujo de eventos de diagnóstico.

## Qué se registra {#what-is-tracked}

- Targets, suites y casos individuales de tests reportados.
- Resultados aprobados, fallidos y omitidos, con duraciones cuando el runner las proporciona.
- Mensajes de fallo proporcionados por el runner en informes de ejecuciones fragmentadas alojadas.
- Intentos de reintento ordenados y resultados inestables cuando un test falla y luego pasa.
- Contexto de rama, commit y CI proporcionado por Once.

La identidad del test usa el nombre nativo del target, la suite y el caso. Los IDs de lote de fragmentación son unidades de planificación, no nombres de tests.

El reporting ordinario de `once test` conserva los resultados y los intentos de reintento, pero actualmente no incluye mensajes de fallo en el historial compartido de tests. Los informes de ejecuciones fragmentadas alojadas pueden incluir mensajes de fallo, pero ninguna de las rutas de reporting proporciona ubicaciones de código fuente. Conserva tus logs de CI para diagnósticos que no estén disponibles en Tuist.

No todos los targets de test proporcionan el mismo nivel de detalle. Algunos runners informan casos individuales, otros solo resúmenes; la ejecución exacta por archivo o caso es una capacidad distinta. Consulta [Cobertura del ecosistema de tests de Once](https://buildonce.dev/docs/guide/graph/testing#understand-current-ecosystem-coverage) antes de confiar en análisis por caso o en una planificación granular.

## Tests inestables {#flaky-tests}

Tuist utiliza los intentos reportados y el historial de CI para identificar resultados inconsistentes. Reportar un intento no es lo mismo que habilitar reintentos: configura los reintentos en el runner que los admita. Consulta <.localized_link href="/guides/features/test-insights/flaky-tests/once">Tests inestables con Once</.localized_link> para conocer la detección y el límite actual de cuarentena.

## Selección y cobertura de código {#selection-and-code-coverage}

Once puede seleccionar tests de forma conservadora desde su grafo local con `--changed-path`. Esta es la selección propia de Once, no la selección de tests basada en cobertura alojada de Tuist:

```bash
once test --changed-path src/library.rs
```

El reporting nativo de Once actualmente no sube la cobertura de código a Tuist. Un informe de test exitoso o un plan de fragmentación no rellenan el panel de Cobertura de código.

## Solución de problemas {#troubleshooting}

Si falta una ejecución, comprueba que el proveedor de caché efectivo tenga el nombre de tu proyecto de Tuist y vuelve a autenticarte con `once auth login --provider tuist`. El reporting en tiempo real es de mejor esfuerzo y no convierte un comando de test que de otro modo sería exitoso en un fallo cuando el servicio de reporting no está disponible.

Los resúmenes de ejecución y los fallos estructurados de tests no son logs completos del proceso. Este servidor actualmente no ingiere el flujo de logs de acciones sin procesar de Once; conserva tus logs de CI para la salida que no esté incluida en los resultados estructurados.
