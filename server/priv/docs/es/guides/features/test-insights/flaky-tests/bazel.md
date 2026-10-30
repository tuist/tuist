---
{
  "title": "Bazel Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect flaky Bazel tests, mute their failures, and skip quarantined targets."
}
---

# Tests inestables de Bazel {#bazel-flaky-tests}

`tuist bazel test` obtiene la política de cuarentena de Tuist antes de cada invocación y la aplica a la ejecución subyacente de `bazel test`.

## Aplicar cuarentena {#applying-quarantine}

En la página de un test, cambia su estado a **Silenciado** y luego ejecuta:

```sh
tuist bazel test -- //app:tests
```

Los argumentos después de `--` se reenvían a `bazel test`. Usa `--path` para seleccionar el proyecto y el directorio de trabajo, y `--bazel` para seleccionar un ejecutable diferente como `bazelisk`. El `bazel test` normal sigue informando los resultados de los tests, pero no obtiene ni aplica las políticas de cuarentena de Tuist.

No se requiere ni una configuración nombrada de Bazel ni reintentos para la cuarentena. Las páginas de **Tests inestables**, **Tests en cuarentena** y los tests individuales admiten los mismos cambios de estado manuales que otros sistemas de compilación. Usa **Configuración → Automatizaciones** para configurar umbrales de inestabilidad, acciones de cuarentena y acciones de recuperación.

### Silenciar {#mute}

Usa **Silenciar** como flujo de trabajo principal de cuarentena. Los casos silenciados siguen ejecutándose, sus fallos permanecen visibles y los casos hermanos sanos siguen afectando al resultado. Las nuevas ejecuciones aportan pruebas para la recuperación sin excluir ningún caso del target.

Tuist lee un archivo local temporal de eventos de compilación y los informes `test.xml` referenciados. Cambia el código de salida por fallo de test de Bazel a éxito solo cuando los informes completos atribuyen cada fallo reportado en cada target fallido a un caso silenciado.

Los errores de compilación, tiempos de espera, ejecuciones interrumpidas, informes faltantes o malformados, flujos de eventos incompletos y fallos fuera del conjunto silenciado conservan el estado de fallo de Bazel. El archivo local de eventos está limitado a 64 mebibytes y los informes individuales a 5 mebibytes. Tuist necesita su propio archivo local de eventos de compilación para verificar los fallos silenciados y recuperarse de targets omitidos obsoletos, por lo que un `--build_event_json_file` explícito no puede combinarse con casos silenciados u omitidos activos. La notificación remota de eventos de compilación sigue configurándose a través de `tuist bazel setup`.

La invocación original de Bazel y los informes conservan sus resultados reales. El servidor de Tuist registra si un caso estaba en cuarentena cuando comenzó la invocación, incluso si su estado cambia antes de que se procese el informe.

### Omitir {#skip}

Usa **Omitir** solo cuando pretendas excluir el **target completo de Bazel**, incluidos los casos sanos dentro de ese target. Marcar un solo caso como **Omitido** tiene este efecto en todo el target. La sintaxis de filtrado por caso individual de Bazel depende del framework de tests y no es compatible universalmente. Por ello, Tuist usa patrones nativos de target negativos con la expansión de suites de tests habilitada. Los targets explícitos, las selecciones con comodines y los tests dentro de reglas `test_suite` mantienen el comportamiento de selección normal de Bazel.

El comando obtiene cada página de cuarentena y elimina duplicados de targets. Si el registro completo de eventos de Bazel identifica un target omitido faltante antes de la configuración o ejecución del target, Tuist lo menciona en una advertencia y reintenta sin esa exclusión obsoleta. Se conservan los patrones solicitados originalmente y todas las demás exclusiones. La recuperación se limita a cinco reintentos; otros fallos de carga y pruebas incompletas conservan el error de Bazel. Devuelve los casos obsoletos a **Habilitado** para eliminar sus políticas permanentemente. Pasa los patrones de target directamente; `--target_pattern_file` no puede combinarse con exclusiones de cuarentena. Si no quedan targets de test, Bazel conserva su estado de salida normal de “no se encontraron tests”, lo que también detecta una selección de tests accidentalmente vacía.

El comando imprime cada etiqueta de target excluido para que los registros de compilación muestren qué targets, incluidos sus casos sanos, excluye la política de cuarentena.

### Volver a ejecutar tests en cuarentena {#running-quarantined-tests-again}

Para investigar o validar una corrección, omite ambas políticas de cuarentena:

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

Devuelve el caso a **Habilitado** para incluir su target en ejecuciones normales posteriores. Los casos omitidos no generan nuevas ejecuciones hasta que se incluyan explícitamente, por lo que una automatización basada en nuevas ejecuciones exitosas necesita una ejecución de validación antes de poder recuperarlos.

Los errores de recuperación de cuarentena detienen el comando antes de ejecutar los tests. El comando también rechaza políticas superiores a 20.000 casos o argumentos de target que superen su tamaño limitado; nunca aplica una política parcial. Usa `--no-quarantine` cuando quieras ejecutar intencionadamente sin la política.

## Configuración opcional y reintentos {#optional-configuration-and-retries}

Si tu repositorio define una configuración llamada `ci` en `.bazelrc`, puedes seleccionarla con `--config=ci`:

```sh
tuist bazel test -- --config=ci //app:tests
```

Esta es una configuración definida por el repositorio, no un requisito previo de Tuist. Omite la opción cuando tu repositorio no la defina.

Los reintentos también son opcionales e independientes de la cuarentena. `--flaky_test_attempts=3` habilita hasta **tres intentos totales de Bazel** por test, no tres reintentos adicionales. Los equipos pueden mantener su configuración de reintentos existente en `.bazelrc` o pasarla explícitamente:

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

Para repositorios que definen `ci`, las opciones se pueden combinar:

```sh
tuist bazel test -- --config=ci --flaky_test_attempts=3 //app:tests
```

## Detección de inestabilidad {#detecting-flakiness}

Tuist utiliza los casos individuales de los informes `test.xml` de Bazel para detectar resultados inconsistentes entre reintentos y entre ejecuciones del mismo commit y selección de targets en integración continua. Las ejecuciones locales permanecen visibles, pero no marcan automáticamente los casos de test como inestables. Proporciona metadatos de commit y rama cuando tu entorno de compilación no los publique ya:

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

Los reintentos deben ejecutarse realmente para que Tuist observe sus resultados. Un resumen de inestabilidad de un target de Bazel por sí solo no identifica qué caso individual fue inestable. Los informes no disponibles o que no se puedan analizar no pueden aportar pruebas a nivel de caso.

Los casos se identifican por la etiqueta del target, el nombre de la clase (con fallback al nombre de la suite) y el nombre del test. Esto mantiene separados los métodos con nombres idénticos en diferentes clases. Los informes antiguos que usaban un nombre de suite contenedora diferente conservan su historial bajo la identidad antigua; su estado de cuarentena debe aplicarse a la nueva identidad. Cuando un fallo coincide con un silenciamiento basado en una suite antigua en lugar de su identidad de clase actual, el comando advierte qué política debe volver a aplicarse y mantiene el fallo como bloqueante. Las políticas no se transfieren automáticamente porque varias clases pueden haber compartido la identidad antigua.

Consulta los [filtros de test](https://bazel.build/docs/user-manual#test-filter), las [opciones de comando](https://bazel.build/reference/command-line-reference) y las [descripciones de eventos de compilación](https://bazel.build/remote/bep-glossary) de Bazel para conocer el comportamiento subyacente.
