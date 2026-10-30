---
{
  "title": "Análisis de tests de Bazel",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Supervisa las métricas de los tests de Bazel en el panel de control de Tuist para monitorizar el rendimiento y la fiabilidad de los tests."
}
---
# Análisis de tests de Bazel {#bazel-test-insights}

Ejecuta tests de Bazel a través de Tuist para alimentar los mismos paneles de tests que usa cualquier otro sistema de compilación:

```bash
tuist bazel test -- //app:tests
```

Los argumentos después de `--` se reenvían a `bazel test`. Usa `--path` para seleccionar el proyecto y el directorio de trabajo, y `--bazel` para seleccionar un ejecutable diferente, como `bazelisk`. Un `bazel test` normal sigue informando de los resultados de los tests, pero no obtiene ni aplica las políticas de cuarentena de Tuist.

> [!NOTE]
> El contenedor `tuist bazel test` solo es necesario para los <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">tests en cuarentena</.localized_link>. El informe por caso para ejecuciones de tests normales lo configura `tuist bazel setup` en `.bazelrc.tuist`, así que un `bazel test` simple también informa de casos individuales.

## Qué se registra {#what-is-tracked}

Tuist analiza los informes `test.xml` y captura la salida de `test.log` que Bazel genera para cada objetivo de test, y luego los consolida en el modelo compartido de ejecuciones de tests. Cada ejecución registra:

- El estado de aprobado, fallido y omitido de cada caso de test, junto con su duración.
- La estructura de objetivos de test, clases y suites.
- Los intentos de reintento, cuando Bazel está configurado para reintentar tests inestables.
- La salida de error, capturada desde el `test.log` del objetivo.

Las páginas de **Ejecuciones de tests**, **Casos de test** y los tests individuales funcionan igual para Bazel que para otros sistemas de compilación.

## Emisión de informes JUnit por caso {#per-case-junit-reports}

Las filas por caso dependen de que el objetivo de test escriba un `test.xml` JUnit en la ruta `$XML_OUTPUT_FILE` que proporciona Bazel. Cuando el runner no escribe uno, Bazel recurre a un informe sintetizado de un solo caso con el nombre del objetivo, y Tuist muestra una única fila por objetivo (etiquetada como **Objetivo de Bazel** en la lista de Casos de test) con el `test.log` sin procesar aún disponible en la página de la ejecución.

La mayoría de las reglas de test de Bazel ya producen un `test.xml` real:

- `java_test` y `kt_jvm_test`: JUnit viene integrado.
- `cc_test` con GoogleTest: el runner escribe JUnit cuando se compila contra una versión reciente de gtest; las configuraciones más antiguas necesitan `--gtest_output=xml:$XML_OUTPUT_FILE`.
- `py_test`: usa pytest con `--junitxml=$XML_OUTPUT_FILE`, o el runner pytest de `rules_python`.
- `go_test`: canaliza `go test -json` a través de `gotestsum --junitfile=$XML_OUTPUT_FILE`, o envuélvelo con un auxiliar que emita JUnit.

`rust_test` de `rules_rust` y `rules_rs` ejecuta el arnés estándar `libtest`, que no escribe JUnit en Rust estable. Envuelve el objetivo de test con un script que analice la salida de `libtest` y escriba JUnit en `$XML_OUTPUT_FILE`; así mantienes las filas por caso en Tuist y la misma ejecución sigue siendo un único objetivo de test de Bazel.

## Identidad del test {#test-identity}

Los casos se identifican por la etiqueta del objetivo, el nombre de la clase (con fallback al nombre de la suite) y el nombre del test. Esto mantiene separados los métodos con el mismo nombre en distintas clases. Los informes antiguos que usaban un nombre de suite contenedora diferente conservan su historial bajo la identidad antigua; los cambios de estado aplicados a la identidad antigua deben volver a aplicarse a la nueva, y el comando te avisa cuando un fallo coincide con una identidad antigua para que sepas qué política trasladar.

## Proporcionar contexto de CI {#providing-ci-context}

Tuist lee la información del commit y la rama de git desde los metadatos de compilación de Bazel, de modo que las ejecuciones en el mismo commit puedan compararse entre entornos. La mayoría de los sistemas de integración continua ya los establecen; cuando el tuyo no lo haga, pásalos explícitamente:

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

La misma marca `--build_metadata` es la que describe la página de <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Análisis de compilaciones de Bazel</.localized_link> para etiquetar invocaciones, por lo que un único conjunto de marcas cubre ambas funcionalidades.

## Tests inestables y cuarentena {#flaky-tests-and-quarantine}

Los reintentos, la detección de inestabilidad entre ejecuciones y la cuarentena por caso (Silenciar y Omitir) funcionan a través de `tuist bazel test`. Consulta <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Tests inestables de Bazel</.localized_link> para ver el flujo completo.

## Retención de datos {#data-retention}

Tuist conserva durante 90 días la invocación de Bazel que generó una ejecución de tests, sus registros y los registros pendientes de ingesta de tests. Los casos de test y su historial de ejecuciones utilizan el mismo modelo que cualquier otro sistema de compilación y no están sujetos a ese plazo. Consulta la política completa de <.localized_link href="/guides/server/data-retention">retención de datos</.localized_link>.
