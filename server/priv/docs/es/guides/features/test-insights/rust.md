---
{
  "title": "Análisis de tests de Rust",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Haz seguimiento de los resultados de los tests de Cargo, incluidos los doctests de Rust, en el panel de control de Tuist."
}
---
# Análisis de tests de Rust {#rust-test-insights}

Tuist informa los resultados individuales de los tests de `cargo test`, incluidos tests unitarios, tests de integración y doctests. No se requiere ninguna dependencia de Rust ni un ejecutor de tests adicional.

> [!IMPORTANT]
> **Requisitos**
>
> - Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link>.

## Informa tus ejecuciones de tests {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

Con el wrapper de mise para Cargo configurado, puedes seguir escribiendo `cargo test`. Cargo sigue compilando y ejecutando tus tests con sus argumentos, salida y código de salida habituales. Los fallos en el informe no cambian el resultado de tus tests.

Puedes seleccionar un paquete o filtrar tests como de costumbre:

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Qué rastrea Tuist {#what-is-tracked}

- Tests aprobados, fallidos e ignorados de suites de tests completadas.
- Tests unitarios, tests de integración y doctests.
- Duraciones de la suite completa.
- Metadatos disponibles de rama, commit, CI y runner.

Los tests filtrados y los tests no ejecutados tras un fallo nunca se informan como aprobados. Los resultados aparecen bajo **Tests** en el dashboard.

## Integración continua {#continuous-integration}

Tuist reconoce GitHub Actions, GitLab CI, Bitrise, CircleCI, Buildkite y Codemagic, y vincula cada ejecución con su trabajo de CI. En cualquier otro sistema de CI, una ejecución se cuenta como ejecución de CI cuando la variable de entorno `CI` está definida. La mayoría de los sistemas de CI la definen; defínela tú mismo donde no lo hagan, como en Fly.io Machines. La detección de tests inestables solo compara ejecuciones de CI.

Un trabajo que hace checkout de un commit en lugar de una rama deja a Git sin una rama que nombrar, por lo que sus ejecuciones no tienen rama. En los sistemas de CI que Tuist reconoce, la rama proviene del proveedor. En otros casos, asígnale un nombre con `TUIST_GIT_BRANCH`:

```sh
CI=true TUIST_GIT_BRANCH=main tuist cargo test --workspace
```

## Paquetes, módulos y casos de test {#test-hierarchy}

Tuist agrupa los resultados por paquete y target de Cargo. Las rutas de módulos de Rust agrupan tests individuales dentro de un target:

| Etiqueta del dashboard | Significado en Rust | Ejemplo |
| --- | --- | --- |
| Módulos | Paquete y target de Cargo | `store::api` |
| Suites de tests | Rutas de módulos de Rust | `api::authentication` |
| Casos de test | Tests individuales | `rejects_invalid_token` |

Los doctests usan un módulo separado, como `store::doctest/store`. Sus nombres incluyen la ubicación del origen, por lo que mover un ejemplo puede cambiar su identidad.

## Doctests y duraciones {#cargo-test}

Los doctests se ejecutan con tu comando de test habitual, incluidos ejemplos `compile_fail`, `should_panic` y `no_run`. Para ejecutar solo doctests:

```sh
tuist cargo test --doc
```

libtest estable informa el tiempo de la suite completa, pero no las duraciones de tests individuales. Las mediciones no disponibles se excluyen de los historiales de duración por caso y de los análisis de duración, mientras que los resultados de los tests siguen contribuyendo a la fiabilidad y al recuento de ejecuciones.

## Límites de informes {#reporting-limits}

Los resultados individuales se recopilan de la salida predeterminada de Cargo/libtest. Los comandos que usan `--no-run`, `--list`, salida silenciosa o verbosa de Cargo, formatos alternativos o salida de test no capturada se ejecutan normalmente sin informar tests individuales. Los harnesses personalizados, los resúmenes incompletos, la atribución ambigua de targets y los informes demasiado grandes no se suben.

Si los paquetes del workspace tienen targets de integración con el mismo nombre, selecciona uno con `-p <package>`. Los informes admiten nombres exactos de paquetes del workspace; los paquetes de dependencias, los selectores calificados por versión y los patrones glob se ejecutan normalmente, pero no se informan. Las rutas absolutas de doctest se omiten para evitar que las rutas de checkout formen parte de las identidades de los tests.

Tuist transmite la salida mientras recopila los resultados. Esto puede afectar a la detección automática de color. Los procesos en segundo plano que mantienen abiertas las tuberías de salida después de que Cargo finalice pueden provocar que se omita el informe, pero no cambian el estado de salida de Cargo.

## Fiabilidad y selección {#reliability-and-selection}

Usa la <.localized_link href="/guides/features/test-insights/flaky-tests/rust">detección y cuarentena de tests inestables</.localized_link> para investigar tests inestables y silenciarlos u omitirlos. El <.localized_link href="/guides/features/test-sharding/rust">sharding de tests</.localized_link> distribuye targets completos de Cargo entre los workers de CI. Activa la <.localized_link href="/guides/features/test-code-coverage/rust">cobertura de código</.localized_link> para seguir la cobertura de líneas de tus ejecuciones de tests. La selección de tests basada en cobertura y la distribución de compilación única no están disponibles para ejecuciones simples de tests de Cargo.

## Solución de problemas {#troubleshooting}

Si una ejecución de test no aparece en el dashboard, habilita la salida de depuración para ver por qué no se envió su informe:

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
