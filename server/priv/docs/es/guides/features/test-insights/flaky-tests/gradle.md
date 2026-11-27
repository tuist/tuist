---
{
  "title": "Tests inestables en Gradle",
  "titleTemplate": ":title · Tests inestables · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Detecta, gestiona y pon en cuarentena los tests inestables en proyectos Gradle con Tuist."
}
---
# Tests inestables de Gradle {#gradle-flaky-tests}

> [!IMPORTANT]
> **Requisitos**
>
> - <.localized_link href="/guides/features/test-insights/gradle">Análisis de tests de Gradle</.localized_link> configurado.

<!-- @snippet: ./_intro -->

![Página de tests inestables](/images/guides/features/test-insights/flaky-tests-page.png)

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist detecta los tests inestables de dos formas:

### Reintentos de tests {#test-retries}

Cuando ejecutas tests con funcionalidad de reintento, Tuist analiza los resultados de cada intento. Si un test falla en algunos intentos pero pasa en otros, se marca como inestable.

Puedes usar el [plugin Test Retry](https://github.com/gradle/test-retry-gradle-plugin) o un mecanismo similar para volver a ejecutar los tests fallidos. Tuist detectará los tests que pasan en algunos intentos pero fallan en otros.

Añade el plugin a tu `build.gradle.kts`:

```kotlin
plugins {
    id("org.gradle.test-retry") version "1.6.2"
}

tasks.test {
    retry {
        maxRetries = 3
        maxFailures = 5
        failOnPassedAfterRetry = false
    }
}
```

![Detalle del caso de test inestable](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Detección entre ejecuciones {#cross-run-detection}

Incluso sin reintentos de tests, Tuist puede detectar tests inestables comparando resultados entre diferentes ejecuciones de CI en el mismo commit y el mismo proyecto de Gradle. Si un test pasa en una ejecución de CI pero falla en otra para el mismo commit y proyecto, la ejecución fallida se marca como inestable.

El proyecto de Gradle forma parte de la clave de comparación porque el mismo test puede comportarse de forma determinista diferente entre proyectos; por ejemplo, una clase de test compartida compilada con distintas dependencias o ejecutada en un fixture de módulo diferente. Dos ejecuciones del mismo commit en distintos proyectos de Gradle se tratan como variantes de ejecución separadas y no se marcarán mutuamente como inestables.

Esto es especialmente útil para capturar tests inestables que no fallan con la suficiente consistencia como para ser detectados por los reintentos, pero aun así provocan fallos intermitentes en CI.

<!-- @snippet: ./_managing -->

## Poner en cuarentena tests inestables {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Un test en cuarentena está en uno de estos dos modos:

- **Silenciado**: el test sigue ejecutándose, pero el plugin establece `ignoreFailures = true` y solo hace fallar la compilación por fallos no puestos en cuarentena. Los fallos siguen alimentando el detector de tests inestables, así que puedes seguir monitorizando el test sin romper la compilación. Elige esta opción para un test que estés investigando activamente.
- **Omitido**: el plugin filtra el test mediante `excludeTestsMatching` de Gradle, por lo que nunca llega a iniciarse. No genera nuevos resultados y desaparece del panel de tests inestables hasta que lo vuelvas a habilitar. Elige esta opción cuando el test esté roto, sea lento o tan persistentemente inestable que ejecutarlo solo suponga un desperdicio de minutos de CI.

<!-- @snippet: ./_quarantined-passing -->

### Habilitar la cuarentena {#enabling-quarantine}

La cuarentena se **habilita automáticamente en CI** (cuando la variable de entorno `CI` está definida) y se deshabilita para compilaciones locales. El plugin obtiene la lista de tests en cuarentena del servidor de Tuist antes de cada tarea de test; los tests silenciados se ejecutan con normalidad y sus fallos se ocultan, mientras que los tests omitidos se filtran.

Puedes controlar esto explícitamente en tu `settings.gradle.kts`:

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

Cuando `enabled` no está definido, el valor predeterminado es la autodetección: habilitado en CI, deshabilitado en local.

## Pruebas de estrés para tests nuevos {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Un caso de test se considera nuevo cuando no se ha ejecutado en CI en los últimos 90 días en la rama por defecto del proyecto, o en un commit que desde entonces se haya integrado en ella. Con una cola de merge, un caso de test ejecutado por la cola se conoce una vez que el commit de la cola se integra, y sigue siendo nuevo si la cola lo descarta. Los commits se emparejan a través del <.localized_link href="/guides/features/test-insights/gradle#git-history">historial de Git</.localized_link> que Tuist recopila en CI.

<!-- @snippet: ./_stress-modes -->

Decláralo en `settings.gradle.kts`, o define `TUIST_TEST_STRESS_NEW_TESTS` para variar el modo por canal de CI:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

A diferencia de la cuarentena, la puerta de control no tiene un valor predeterminado consciente de CI. Si no se define `mode`, no se ejecuta en ningún sitio.

<!-- @snippet: ./_stress-reruns -->

Cada reintento es una compilación anidada de Gradle filtrada para ese único caso de test, de modo que cada reinteto obtiene una JVM de test nueva.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
