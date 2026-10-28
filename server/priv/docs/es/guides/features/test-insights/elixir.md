---
{
  "title": "Elixir Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the tests of your Elixir project in the Tuist dashboard to monitor test performance."
}
---
# Información de tests de Elixir {#elixir-test-insights}

El paquete Hex de Tuist sube los resultados de los tests de tu proyecto de Elixir después de cada ejecución, ofreciéndote visibilidad sobre el rendimiento de los tests y los tests inestables directamente en el dashboard de Tuist.

> [!IMPORTANT] REQUIREMENTS
> - Completa <.localized_link href="/guides/get-started/elixir-project">Get started with Elixir</.localized_link>

## Reporta tus ejecuciones de tests {#report-your-test-runs}

La configuración compartida instala la integración de tests. Sigue usando `mix test`, con los mismos argumentos, salida y código de salida:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist reporta la ejecución cuando finaliza; no se necesita ningún alias de test adicional.

Puedes acceder a la información de tus tests en el dashboard de Tuist y ver cómo evolucionan con el tiempo:

![Dashboard de tests de una aplicación Phoenix](/images/guides/features/elixir/tests-dashboard.png)

## Qué se rastrea {#what-is-tracked}

El paquete recopila resultados de ExUnit, incluyendo:
- Estado de aprobación/fallo y duración de cada test individual
- El módulo y el bloque `describe` al que pertenece cada test
- El mensaje y la ubicación de cada fallo
- Detección de tests inestables entre ejecuciones
- La rama y el commit, y en integración continua, el proveedor y la ejecución
- En integración continua, el [historial de Git](#git-history) del checkout

Los doctests se reportan como cualquier otro test.

> [!NOTE]
> El paquete reporta a través de un formateador de ExUnit que añade junto a los que ya usas. Si pasas `--formatter` en la línea de comandos, Mix reemplaza toda la lista, por lo que la ejecución no se reporta y la tarea te advierte sobre ello.

### Historial de Git {#git-history}

En integración continua, el paquete también sube el historial de commits del checkout: SHAs de los commits, sus padres, fechas de los commits y la rama en la que estaban la ejecución y la rama base de su pull request. No se suben contenidos de archivos, mensajes de commit ni autores. Esto es lo que le indica a Tuist qué commits llegaron a tu rama predeterminada, por ejemplo, los que probó una cola de fusión. El paquete lee el historial que ya tiene el checkout y, cuando el checkout no tiene la rama base, solicita al remoto su último commit (`git ls-remote`). Fuera de la cobertura de código (`--cover`), no obtiene el historial.

| Variable | Efecto |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | No lee ni sube ningún historial de Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Lee solo el checkout, sin contactar con el remoto. |

## Solución de problemas {#troubleshooting}

El reporte nunca cambia el resultado de tus tests: si el reporte no puede enviarse, la ejecución termina como habría terminado y no se imprime nada. Para ver por qué no se envió un reporte, establece `TUIST_DEBUG=1`:

```bash
TUIST_DEBUG=1 mix test
```
