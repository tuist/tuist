---
{
  "title": "Tests inestables de Bazel",
  "titleTemplate": ":title · Tests inestables · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Detecta tests inestables de Bazel, silencia sus fallos y omite los objetivos en cuarentena."
}
---
# Tests inestables de Bazel {#bazel-flaky-tests}

> [!IMPORTANT]
> **Requisitos**
>
> - <.localized_link href="/guides/features/test-insights/bazel">Análisis de tests de Bazel</.localized_link> configurado mediante `tuist bazel setup`.

<!-- @snippet: ./_intro -->

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist utiliza los casos individuales de los informes `test.xml` de Bazel para detectar resultados inconsistentes entre reintentos y entre ejecuciones de la misma confirmación y selección de objetivos en integración continua. Las ejecuciones locales siguen siendo visibles, pero no marcan automáticamente los casos de test como inestables.

### Reintentos de tests {#test-retries}

Los reintentos son opcionales e independientes de la cuarentena. `--flaky_test_attempts=3` habilita hasta **tres intentos totales de Bazel** por test, no tres reintentos adicionales. Mantén tu configuración de reintentos existente en `.bazelrc` o pásala explícitamente:

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

Los reintentos deben ejecutarse realmente para que Tuist observe sus resultados. El resumen de inestabilidad de un objetivo de Bazel por sí solo no identifica qué caso individual fue inestable.

### Detección entre ejecuciones {#cross-run-detection}

Comparar ejecuciones requiere metadatos de confirmación y rama. Proporciónalos cuando tu entorno de compilación no los publique ya:

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

Los casos se identifican por la etiqueta del objetivo, el nombre de la clase (con fallback al nombre de la suite) y el nombre del test, como se describe en <.localized_link href="/guides/features/test-insights/bazel">Análisis de tests de Bazel</.localized_link>.

<!-- @snippet: ./_managing -->

## Poner en cuarentena tests inestables {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test` obtiene la política de cuarentena antes de cada invocación y la aplica a la ejecución subyacente de `bazel test`. Un `bazel test` normal sigue informando de los resultados de los tests, pero no aplica la cuarentena:

```sh
tuist bazel test -- //app:tests
```

Los argumentos después de `--` se reenvían a `bazel test`. Usa `--path` para seleccionar el proyecto y el directorio de trabajo, y `--bazel` para seleccionar un ejecutable diferente, como `bazelisk`. Una configuración de Bazel con nombre, como `--config=ci`, es opcional y funciona de la misma manera.

### Silenciar {#mute}

Usa **Silenciar** como flujo de trabajo principal de cuarentena. Los casos silenciados siguen ejecutándose, sus fallos permanecen visibles y los casos hermanos sanos siguen afectando al resultado. Tuist convierte la salida de fallo de test de Bazel en éxito solo cuando los informes atribuyen cada fallo en cada objetivo fallido a un caso silenciado. Los errores de compilación, los tiempos de espera agotados, las ejecuciones interrumpidas, los informes faltantes o incompletos y los fallos fuera del conjunto silenciado mantienen el estado de fallo de Bazel.

### Omitir {#skip}

La omisión funciona por objetivo de Bazel: omitir un caso excluye todo su objetivo, incluidos los casos sanos, porque Bazel no puede filtrar casos individuales para cada framework de tests. Prefiere **Silenciar** a menos que pretendas excluir el objetivo completo. El comando imprime todas las etiquetas de objetivo excluidas para que los registros de compilación muestren qué dejó fuera la política de cuarentena.

Si un objetivo omitido ya no existe, Tuist lo nombra en una advertencia y se ejecuta sin esa exclusión. Devuelve los casos obsoletos a **Habilitado** para eliminar sus políticas permanentemente. Si no queda ningún objetivo de test, Bazel mantiene su estado de salida normal de "no se encontraron tests".

<!-- @snippet: ./_quarantined-passing -->

### Volver a ejecutar tests en cuarentena {#running-quarantined-tests-again}

Para investigar o validar una corrección, omite la política de cuarentena:

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

Devuelve el caso a **Habilitado** para incluir su objetivo en ejecuciones normales posteriores. Los casos omitidos no generan nuevas ejecuciones hasta que se incluyan explícitamente, por lo que una automatización basada en nuevas ejecuciones exitosas necesita una ejecución de validación antes de poder recuperarlos.

### Limitaciones {#limitations}

- Un `--build_event_json_file` o `--target_pattern_file` explícito no se puede combinar con una cuarentena activa. Pasa los patrones de objetivo directamente.
- Si Tuist no puede obtener la política de cuarentena, el comando se detiene antes de ejecutar los tests. Nunca aplica una política parcial. Usa `--no-quarantine` cuando quieras ejecutar intencionadamente sin ella.
- Un fallo que coincide con un silenciamiento registrado bajo una identidad anterior basada en la suite sigue siendo bloqueante, y el comando nombra la política que debe volver a aplicarse.

Consulta los [filtros de tests](https://bazel.build/docs/user-manual#test-filter), las [opciones de comando](https://bazel.build/reference/command-line-reference) y las [descripciones de eventos de compilación](https://bazel.build/remote/bep-glossary) de Bazel para conocer el comportamiento subyacente.

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
