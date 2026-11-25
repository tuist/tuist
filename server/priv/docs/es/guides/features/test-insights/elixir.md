---
{
  "title": "Análisis de tests de Elixir",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Realiza un seguimiento de los tests de tu proyecto de Elixir en el panel de control de Tuist para supervisar su rendimiento."
}
---
# Análisis de tests de Elixir {#elixir-test-insights}

El paquete Hex de Tuist sube los resultados de los tests de tu proyecto Elixir tras cada ejecución de tests, lo que te permite ver el rendimiento de los tests y detectar tests inestables directamente en el panel de Tuist.

> [!IMPORTANT]
> **Requisitos**
>
> - Completa <.localized_link href="/guides/get-started/elixir-project">Primeros pasos con Elixir</.localized_link>

## Informa de tus ejecuciones de tests {#report-your-test-runs}

La configuración compartida instala la integración de tests. Sigue usando `mix test`, con los mismos argumentos, salida y código de salida:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist informa de la ejecución cuando finaliza; no hace falta ningún alias adicional para los tests.

Puedes acceder a tus análisis de tests en el panel de Tuist y ver cómo evolucionan con el tiempo:

![Panel de tests de una aplicación Phoenix](/images/guides/features/elixir/tests-dashboard.png)

## Qué se registra {#what-is-tracked}

El paquete recopila resultados de ExUnit, entre ellos:
- Estado de aprobado/suspenso y duración de cada test individual
- El módulo y el bloque `describe` al que pertenece cada test
- El mensaje y la ubicación de cada fallo
- Detección de tests inestables entre ejecuciones
- La rama y el commit y, en integración continua, el proveedor y la ejecución
- En integración continua, el [historial de Git](#git-history) del checkout

Los doctests se informan como cualquier otro test. Con `--cover`, también se sube la cobertura de líneas de la ejecución: consulta <.localized_link href="/guides/features/test-code-coverage/elixir">Cobertura de código en Elixir</.localized_link>.

> [!NOTE]
> El paquete informa a través de un formateador de ExUnit que añade junto a los que ya uses. Si pasas `--formatter` en la línea de comandos, Mix reemplaza toda la lista, por lo que la ejecución no se informa y la tarea te avisa de ello.

### Historial de Git {#git-history}

En integración continua, el paquete también sube el historial de commits del checkout: SHAs de los commits, sus padres, fechas de los commits y la rama en la que estaban la ejecución y la rama base de su pull request. No se suben contenidos de archivos, mensajes de commit ni autores. Esto es lo que indica a Tuist qué commits llegaron a tu rama predeterminada, por ejemplo los que probó una cola de merge. El paquete lee el historial que ya tiene el checkout y, cuando el checkout no tiene la rama base, solicita al remoto su último commit (`git ls-remote`). Fuera de la cobertura de código (`--cover`), no obtiene el historial. Con cobertura de código, se profundiza un checkout superficial, sin contenidos de archivo, para encontrar dónde se bifurcó una pull request y, en integración continua, para alcanzar los commits que Tuist ya tiene, de modo que nunca se sube un commit sin el padre sobre el que se asienta.

| Variable | Efecto |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | No lee ni sube ningún historial de Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Lee solo el checkout, sin contactar con el remoto. |
| `TUIST_GIT_BRANCH=<branch>` | Asigna un nombre a la rama de la ejecución, por delante de la del proveedor de CI y del checkout. Configúrala en sistemas de CI que Tuist no reconoce y que hacen checkout de un commit en lugar de una rama, cuyas ejecuciones de otro modo no tendrían rama. |

## Solución de problemas {#troubleshooting}

Informar nunca cambia el resultado de tus tests: si el informe no puede enviarse, la ejecución termina como habría terminado y no se imprime nada. Para ver por qué no se envió un informe, establece `TUIST_DEBUG=1`:

```bash
TUIST_DEBUG=1 mix test
```
