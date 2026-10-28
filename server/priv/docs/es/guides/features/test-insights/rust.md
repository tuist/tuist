---
{
  "title": "Rust Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Cargo test results, including Rust doctests, in the Tuist dashboard."
}
---
# Información de tests de Rust {#rust-test-insights}

Tuist informa los resultados individuales de los tests de `cargo test`, incluyendo unit tests, integration tests y doctests. No se requiere ninguna dependencia de Rust ni un ejecutor de tests adicional.

> [!IMPORTANT] Requirements
> - Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link>.

## Informa tus ejecuciones de tests {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

Con el wrapper de mise para Cargo configurado, puedes seguir escribiendo `cargo test`. Cargo sigue compilando y ejecutando tus tests, con sus argumentos, salida y código de salida habituales. Los fallos en el envío de informes no cambian el resultado de tus tests.

Puedes seleccionar un paquete o filtrar tests como de costumbre:

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Qué rastrea Tuist {#what-is-tracked}

- Tests pasados, fallidos e ignorados de suites de tests completadas.
- Unit tests, integration tests y doctests.
- Duraciones de la suite completa.
- Metadatos disponibles de rama, commit, CI y runner.

Los tests filtrados y los tests no ejecutados tras un fallo nunca se informan como pasados. Los resultados aparecen bajo **Tests** en el dashboard.

## Paquetes, módulos y casos de test {#test-hierarchy}

Tuist agrupa los resultados por paquete y target de Cargo. Las rutas de módulo de Rust agrupan tests individuales dentro de un target:

| Etiqueta del dashboard | Significado en Rust | Ejemplo |
| --- | --- | --- |
| Módulos | Paquete y target de Cargo | `store::api` |
| Suites de tests | Rutas de módulo de Rust | `api::authentication` |
| Casos de test | Tests individuales | `rejects_invalid_token` |

Los doctests usan un módulo separado como `store::doctest/store`. Sus nombres incluyen la ubicación del origen, por lo que mover un ejemplo puede cambiar su identidad.

## Doctests y duraciones {#cargo-test}

Los doctests se ejecutan con tu comando de test habitual, incluyendo ejemplos `compile_fail`, `should_panic` y `no_run`. Para ejecutar solo doctests:

```sh
tuist cargo test --doc
```

libtest estable informa el tiempo de la suite completa pero no las duraciones de tests individuales. Los tiempos no disponibles se excluyen de los historiales de duración por caso y de las analíticas de duración, mientras que los resultados de los tests siguen contribuyendo a la fiabilidad y al recuento de ejecuciones.

## Límites de informe {#reporting-limits}

Los resultados individuales se recogen de la salida predeterminada de Cargo/libtest. Los comandos que usan `--no-run`, `--list`, salida silenciosa o verbosa de Cargo, formatos alternativos o salida de test no capturada se ejecutan normalmente sin informar tests individuales. Los harnesses personalizados, resúmenes incompletos, atribución ambigua de targets e informes excesivamente grandes no se suben.

Si los paquetes del workspace tienen targets de integración con nombres idénticos, selecciona uno con `-p <package>`. El informe admite nombres exactos de paquetes del workspace; los paquetes de dependencias, selectores calificados por versión y globs se ejecutan normalmente pero no se informan. Las rutas absolutas de doctest se omiten para mantener las rutas de checkout fuera de las identidades de los tests.

Tuist transmite la salida mientras recoge los resultados. Esto puede afectar a la detección automática de color. Los procesos en segundo plano que mantienen abiertas las tuberías de salida después de que Cargo finalice pueden hacer que se omita el informe, pero no cambian el estado de salida de Cargo.

## Fiabilidad y selección {#reliability-and-selection}

Usa la <.localized_link href="/guides/features/test-insights/flaky-tests/rust">detección de tests inestables</.localized_link> para investigar tests inestables. La cuarentena del dashboard actualmente no silencia ni omite los tests de Cargo. La ingesta de cobertura, la selección de tests basada en cobertura y el sharding de construcción única no están disponibles para ejecuciones simples de tests de Cargo.

## Solución de problemas {#troubleshooting}

Si una ejecución de test no aparece en el dashboard, habilita la salida de depuración para ver por qué no se envió su informe:

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
