---
{
  "title": "Análisis de tests de Rust",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Rastrea los resultados de los tests de Cargo, incluidos los doctests de Rust, en el panel de Tuist."
}
---
# Análisis de tests en Rust {#rust-test-insights}

Tuist informa los resultados individuales de los tests obtenidos con `cargo test`, incluidos tests unitarios, tests de integración y doctests. No se requiere ninguna dependencia de Rust ni un ejecutor de tests adicional.

> [!IMPORTANT] Requirements
> - Sigue la <.localized_link href="/guides/get-started/rust-project">configuración del proyecto Rust</.localized_link>.

## Informa tus ejecuciones de tests {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

Con el wrapper de mise para Cargo configurado, puedes seguir escribiendo `cargo test`. Cargo sigue compilando y ejecutando tus tests, con sus argumentos, salida y código de salida habituales. Los fallos al informar no cambian el resultado de tus tests.

Puedes seleccionar un paquete o filtrar tests como de costumbre:

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Qué registra Tuist {#what-is-tracked}

- Tests aprobados, fallidos e ignorados procedentes de suites de tests completadas.
- Tests unitarios, tests de integración y doctests.
- Duraciones de la suite completa.
- Metadatos disponibles de rama, commit, CI y runner.

Los tests filtrados y los tests no ejecutados tras un fallo nunca se informan como aprobados. Los resultados aparecen bajo **Tests** en el dashboard.

## Paquetes, módulos y casos de test {#test-hierarchy}

Tuist agrupa los resultados por paquete y target de Cargo. Las rutas de módulo de Rust agrupan los tests individuales dentro de un target:

| Etiqueta del dashboard | Significado en Rust | Ejemplo |
| --- | --- | --- |
| Módulos | Paquete y target de Cargo | `store::api` |
| Suites de tests | Rutas de módulo de Rust | `api::authentication` |
| Casos de test | Tests individuales | `rejects_invalid_token` |

Los doctests usan un módulo separado, como `store::doctest/store`. Sus nombres incluyen la ubicación del origen, por lo que mover un ejemplo puede cambiar su identidad.

## Doctests y duraciones {#cargo-test}

Los doctests se ejecutan con tu comando de test habitual, incluidos ejemplos `compile_fail`, `should_panic` y `no_run`. Para ejecutar solo doctests:

```sh
tuist cargo test --doc
```

La libtest estable informa el tiempo de la suite completa, pero no las duraciones de tests individuales. Las mediciones no disponibles se excluyen de los historiales de duración por caso y de los análisis de duración, mientras que los resultados de los tests siguen contribuyendo a la fiabilidad y al recuento de ejecuciones.

## Límites de informe {#reporting-limits}

Los resultados individuales se recogen de la salida predeterminada de Cargo/libtest. Los comandos que usan `--no-run`, `--list`, salida silenciosa o verbosa de Cargo, formatos alternativos o salida de test no capturada se ejecutan con normalidad sin informar de tests individuales. Los harnesses personalizados, los resúmenes incompletos, la atribución ambigua de targets y los informes excesivamente grandes no se suben.

Si los paquetes del workspace tienen targets de integración con el mismo nombre, selecciona uno con `-p <package>`. El informe admite nombres exactos de paquetes del workspace; los paquetes de dependencias, los selectores calificados por versión y los patrones glob se ejecutan con normalidad, pero no se informan. Las rutas absolutas de doctest se omiten para evitar que las rutas de checkout formen parte de las identidades de los tests.

Tuist transmite la salida mientras recoge los resultados. Esto puede afectar a la detección automática de color. Los procesos en segundo plano que mantienen abiertas las tuberías de salida después de que Cargo finalice pueden provocar que se omita el informe, pero no cambian el estado de salida de Cargo.

## Fiabilidad y selección {#reliability-and-selection}

Usa la <.localized_link href="/guides/features/test-insights/flaky-tests/rust">detección y cuarentena de tests inestables</.localized_link> para investigar tests inestables y silenciarlos u omitirlos. La <.localized_link href="/guides/features/test-sharding/rust">distribución de tests</.localized_link> reparte targets completos de Cargo entre workers de CI. La ingesta de cobertura, la selección de tests basada en cobertura y la distribución con una única compilación no están disponibles para ejecuciones simples de tests de Cargo.

## Solución de problemas {#troubleshooting}

Si una ejecución de tests no aparece en el dashboard, habilita la salida de depuración para ver por qué no se envió su informe:

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
