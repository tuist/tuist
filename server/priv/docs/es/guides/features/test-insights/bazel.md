---
{
  "title": "Análisis de tests de Bazel",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Realiza un seguimiento de las analíticas de tests de Bazel en el panel de control de Tuist para supervisar el rendimiento y la fiabilidad de los tests."
}
---
# Análisis de tests de Bazel {#bazel-test-insights}

> [!IMPORTANT]
> **Requisitos**
>
> - Un espacio de trabajo de Bazel conectado mediante `tuist bazel setup`, como se describe en <.localized_link href="/guides/get-started/bazel-project">Primeros pasos con un proyecto de Bazel</.localized_link>.

`tuist bazel setup` configura el informe por caso en `.bazelrc.tuist`, de modo que un `bazel test` normal envía casos de test individuales a los mismos paneles que usan todos los demás sistemas de compilación:

```bash
bazel test //app:tests
```

Para aplicar también la <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">cuarentena</.localized_link>, ejecuta los tests a través del wrapper de Tuist. Los argumentos que van después de `--` se reenvían a `bazel test`:

```bash
tuist bazel test -- //app:tests
```

## Qué se registra {#what-is-tracked}

Tuist analiza los informes `test.xml` y captura la salida de `test.log` que Bazel genera para cada objetivo de test; luego los consolida en el modelo compartido de ejecuciones de tests. Cada ejecución registra:

- El estado de aprobado, fallido y omitido de cada caso de test, junto con su duración.
- La estructura de objetivos de test, clases y suites.
- Los intentos de reintento, cuando Bazel está configurado para reintentar tests inestables.
- La salida de error, capturada desde el `test.log` del objetivo.

Las páginas de **Ejecuciones de tests**, **Casos de test** y de tests individuales funcionan igual para Bazel que para otros sistemas de compilación.

## Generación de informes JUnit por caso {#per-case-junit-reports}

Las filas por caso dependen de que el objetivo de test escriba un JUnit `test.xml` en la ruta `$XML_OUTPUT_FILE` que proporciona Bazel. Cuando el runner no escribe uno, Bazel recurre a un informe sintetizado de un solo caso con el nombre del objetivo, y Tuist muestra una única fila por objetivo (etiquetada como **Objetivo de Bazel** en la lista de Casos de test) con el `test.log` sin procesar aún disponible en la página de la ejecución.

La mayoría de las reglas de test de Bazel ya producen un `test.xml` real:

- `java_test` y `kt_jvm_test`: JUnit está integrado.
- `cc_test` con GoogleTest: el runner escribe JUnit cuando se compila contra una versión reciente de gtest; las configuraciones más antiguas necesitan `--gtest_output=xml:$XML_OUTPUT_FILE`.
- `py_test`: usa pytest con `--junitxml=$XML_OUTPUT_FILE`, o el runner pytest de `rules_python`.
- `go_test`: canaliza `go test -json` a través de `gotestsum --junitfile=$XML_OUTPUT_FILE`, o envuélvelo con un helper que emita JUnit.

`rust_test` de `rules_rust` y `rules_rs` ejecuta el harness estándar `libtest`, que no escribe JUnit en Rust estable. Envuelve el objetivo de test con un script que analice la salida de `libtest` y escriba JUnit en `$XML_OUTPUT_FILE`; así mantienes las filas por caso en Tuist y la misma ejecución sigue siendo un único objetivo de test de Bazel.

## Identidad del test {#test-identity}

Los casos se identifican por la etiqueta del objetivo, el nombre de la clase (con fallback al nombre de la suite) y el nombre del test. Esto mantiene separados los métodos con el mismo nombre en distintas clases. Los informes antiguos que usaban un nombre de suite contenedora diferente conservan su historial bajo la identidad antigua; los cambios de estado aplicados a la identidad antigua deben volver a aplicarse a la nueva, y el comando te avisa cuando un fallo coincide con una identidad antigua para que sepas qué política trasladar.

## Proporcionar contexto de CI {#providing-ci-context}

Tuist lee la información del commit y la rama de git a partir de los metadatos de compilación de Bazel, de modo que las ejecuciones en el mismo commit puedan compararse entre entornos. La mayoría de los sistemas de integración continua ya los establecen; cuando el tuyo no lo haga, pásalos explícitamente:

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

La misma bandera `--build_metadata` es la que describe la página de <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Análisis de compilaciones de Bazel</.localized_link> para etiquetar invocaciones, así que un único conjunto de banderas cubre ambas superficies.

## Tests inestables y cuarentena {#flaky-tests-and-quarantine}

Los reintentos, la detección de inestabilidad entre ejecuciones y la cuarentena por caso (Silenciar y Omitir) funcionan a través de `tuist bazel test`. Consulta <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Tests inestables de Bazel</.localized_link> para ver el flujo completo.

## Retención de datos {#data-retention}

Tuist conserva durante 90 días la invocación de Bazel que generó una ejecución de test, sus registros y los registros pendientes de ingesta de tests. Los casos de test y su historial de ejecuciones usan el mismo modelo que cualquier otro sistema de compilación y no están sujetos a ese periodo. Consulta <.localized_link href="/guides/server/data-retention">retención de datos</.localized_link> para conocer la política completa.
