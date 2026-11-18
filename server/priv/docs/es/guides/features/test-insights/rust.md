---
{
  "title": "Análisis de tests de Rust",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Sigue los resultados de los tests de Cargo, incluidos los doctests de Rust, en el panel de control de Tuist."
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

Con el wrapper de mise para Cargo configurado, puedes seguir escribiendo `cargo test`. Cargo sigue compilando y ejecutando tus tests, con sus argumentos, salida y código de salida habituales. Los fallos en el informe no cambian el resultado de tus tests.

Puedes seleccionar un paquete o filtrar tests como de costumbre:

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Qué rastrea Tuist {#what-is-tracked}

- Tests pasados, fallidos e ignorados de suites de tests completadas.
- Tests unitarios, tests de integración y doctests.
- Duraciones de la suite completa.
- Metadatos disponibles de rama, commit, CI y runner.

Los tests filtrados y los tests no ejecutados tras un fallo nunca se informan como pasados. Los resultados aparecen bajo **Tests** en el dashboard.

## Paquetes, módulos y casos de test {#test-hierarchy}

Tuist agrupa los resultados por paquete y target de Cargo. Las rutas de módulo de Rust agrupan los tests individuales dentro de un target:

| Etiqueta del dashboard | Significado en Rust | Ejemplo |
| --- | --- | --- |
| Módulos | Paquete y target de Cargo | `store::api` |
| Suites de tests | Rutas de módulo de Rust | `api::authentication` |
| Casos de test | Tests individuales | `rejects_invalid_token` |

Los doctests usan un módulo separado como `store::doctest/store`. Sus nombres incluyen la ubicación del origen, por lo que mover un ejemplo puede cambiar su identidad.

## Doctests y duraciones {#cargo-test}

Los doctests se ejecutan con tu comando de test habitual, incluidos los ejemplos `compile_fail`, `should_panic` y `no_run`. Para ejecutar solo doctests:

```sh
tuist cargo test --doc
```

libtest estable informa el tiempo de la suite completa, pero no las duraciones de los tests individuales. Las mediciones no disponibles se excluyen de los historiales de duración por caso y de los análisis de duración, mientras que los resultados de los tests siguen contribuyendo a la fiabilidad y al recuento de ejecuciones.

## Límites de informes {#reporting-limits}

Los resultados individuales se recopilan de la salida predeterminada de Cargo/libtest. Los comandos que usan `--no-run`, `--list`, salida silenciosa o verbosa de Cargo, formatos alternativos o salida de test no capturada se ejecutan normalmente sin informar de tests individuales. Los harnesses personalizados, los resúmenes incompletos, la atribución ambigua de targets y los informes excesivamente grandes no se suben.

Si los paquetes del workspace tienen targets de integración con el mismo nombre, selecciona uno con `-p <package>`. Los informes admiten nombres exactos de paquetes del workspace; los paquetes de dependencias, los selectores calificados por versión y los patrones glob se ejecutan normalmente, pero no se informan. Las rutas absolutas de los doctests se omiten para mantener las rutas de checkout fuera de las identidades de los tests.

Tuist transmite la salida mientras recopila los resultados. Esto puede afectar a la detección automática de color. Los procesos en segundo plano que mantienen abiertas las tuberías de salida después de que Cargo finalice pueden hacer que se omita el informe, pero no cambian el estado de salida de Cargo.

## Fiabilidad y selección {#reliability-and-selection}

Usa la <.localized_link href="/guides/features/test-insights/flaky-tests/rust">detección y cuarentena de tests inestables</.localized_link> para investigar tests inestables y silenciarlos u omitirlos. El <.localized_link href="/guides/features/test-sharding/rust">sharding de tests</.localized_link> distribuye targets completos de Cargo entre los workers de CI. Activa la <.localized_link href="/guides/features/test-code-coverage/rust">cobertura de código</.localized_link> para seguir la cobertura de líneas de tus ejecuciones de tests. La selección de tests basada en la cobertura y la distribución de build-once no están disponibles para ejecuciones de test de Cargo simples.

## Solución de problemas {#troubleshooting}

Si una ejecución de test no aparece en el dashboard, habilita la salida de depuración para ver por qué no se envió su informe:

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
