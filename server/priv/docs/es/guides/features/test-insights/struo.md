---
{
  "title": "Análisis de tests de Struo",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Inspecciona suites de tests de Struo, resultados individuales, fallos y duraciones en el panel de Tuist."
}
---
# Análisis de tests de Struo {#struo-test-insights}

<a id="once-test-insights"></a>

Struo envía los resultados de los tests a Tuist para que puedas seguir tu suite en ejecuciones locales y de CI, investigar fallos y encontrar tests lentos sin tener que recopilar informes de cada worker.

> [!IMPORTANT]
> **Requisitos**
>
> - Completa <.localized_link href="/guides/get-started/struo-project">Primeros pasos con Struo</.localized_link>.
> - Usa targets de test que informen resultados estructurados. El nivel de detalle disponible depende del tipo de target y del runner de tests.

## Informa tus ejecuciones de tests {#report-your-test-runs}

Ejecuta toda la suite o selecciona un target:

```bash
struo test
struo test MyTests
```

Struo transmite eventos nativos de tests y publica los resultados completados en el modelo compartido de tests de Tuist. **Tests** y **Ejecuciones de tests** muestran las ejecuciones; los casos individuales también tienen un historial compartido de tests. Una <.localized_link href="/guides/features/test-sharding/struo">ejecución fragmentada alojada</.localized_link> publica un informe por worker en una ejecución combinada en lugar de volver a contabilizar su flujo de eventos de diagnóstico.

## Qué se registra {#what-is-tracked}

- Targets, suites y casos individuales de tests reportados.
- Resultados aprobados, fallidos y omitidos, con duraciones cuando el runner las proporciona.
- Mensajes de fallo proporcionados por el runner en informes de ejecuciones fragmentadas alojadas.
- Intentos de reintento ordenados y resultados inestables cuando un test falla y luego pasa.
- Contexto de rama, commit y CI proporcionado por Struo.

La identidad del test usa el nombre nativo del target, la suite y el caso. Los IDs de lote de fragmentación son unidades de planificación, no nombres de tests.

El reporting habitual de `struo test` conserva los resultados y los intentos de reintento, pero actualmente no incluye mensajes de fallo en el historial compartido de tests. Los informes de ejecuciones fragmentadas alojadas pueden incluir mensajes de fallo, pero ninguna de las rutas de reporting proporciona ubicaciones de origen. Conserva tus logs de CI para diagnósticos que no estén disponibles en Tuist.

No todos los targets de test proporcionan el mismo nivel de detalle. Algunos runners informan casos individuales, otros solo resúmenes; la ejecución exacta por archivo o caso es una capacidad separada. Consulta [Cobertura del ecosistema de tests de Struo](https://struo.run/docs/guide/graph/testing#understand-current-ecosystem-coverage) antes de confiar en análisis por caso o en una planificación granular.

## Tests inestables {#flaky-tests}

Tuist utiliza los intentos reportados y el historial de CI para identificar resultados inconsistentes. Reportar un intento no es lo mismo que habilitar reintentos: configura los reintentos en el runner que los admita. Consulta <.localized_link href="/guides/features/test-insights/flaky-tests/struo">Tests inestables de Struo</.localized_link> para conocer la detección y el límite actual de cuarentena.

## Selección y cobertura de código {#selection-and-code-coverage}

Struo puede seleccionar tests de forma conservadora desde su grafo local con `--changed-path`. Esa es la selección propia de Struo, no la selección de tests basada en cobertura alojada de Tuist:

```bash
struo test --changed-path src/library.rs
```

El reporting nativo de Struo no sube actualmente la cobertura de código a Tuist. Un informe de test exitoso o un plan de fragmentación no rellenan el panel de Cobertura de código.

## Solución de problemas {#troubleshooting}

Si falta una ejecución, comprueba que el proveedor de caché efectivo tenga el nombre de tu proyecto de Tuist y vuelve a autenticarte con `struo auth login --provider tuist`. El reporting en tiempo real es de mejor esfuerzo y no convierte un comando de test que por lo demás sería exitoso en un fallo cuando el servicio de reporting no está disponible.

Los resúmenes de ejecución y los fallos estructurados de tests no son logs completos del proceso. Este servidor no ingiere actualmente el flujo de logs de acciones en bruto de Struo; conserva tus logs de CI para la salida que no se incluye en los resultados estructurados.
