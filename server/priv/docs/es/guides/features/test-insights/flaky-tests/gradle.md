---
{
  "title": "Gradle Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Gradle projects with Tuist."
}
---
# Tests inestables de Gradle {#gradle-flaky-tests}

Los tests inestables son tests que producen resultados diferentes (éxito o fallo) cuando se ejecutan varias veces con el mismo código. Minan la confianza en tu suite de tests y hacen perder tiempo a los desarrolladores investigando fallos falsos. Tuist detecta automáticamente los tests inestables y te ayuda a rastrearlos a lo largo del tiempo.

![Página de Tests Inestables](/images/guides/features/test-insights/flaky-tests-page.png)

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist detecta los tests inestables de dos maneras:

### Reintentos de tests {#test-retries}

Cuando ejecutas tests con funcionalidad de reintento, Tuist analiza los resultados de cada intento. Si un test falla en algunos intentos pero tiene éxito en otros, se marca como inestable.

Puedes usar el [plugin Test Retry](https://github.com/gradle/test-retry-gradle-plugin) o un mecanismo similar para volver a ejecutar los tests fallidos. Tuist detectará los tests que tienen éxito en algunos intentos pero fallan en otros.

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

Incluso sin reintentos de tests, Tuist puede detectar tests inestables comparando resultados entre diferentes ejecuciones de CI en el mismo commit y el mismo proyecto de Gradle. Si un test tiene éxito en una ejecución de CI pero falla en otra ejecución para el mismo commit y proyecto, ambas ejecuciones se marcan como inestables.

El proyecto de Gradle forma parte de la clave de comparación porque el mismo test puede comportarse de manera determinista diferente entre proyectos — por ejemplo, una clase de test compartida compilada con diferentes dependencias o ejecutada en un fixture de módulo diferente. Dos ejecuciones del mismo commit en diferentes proyectos de Gradle se tratan como variantes de ejecución separadas y no se marcarán mutuamente como inestables.

Esto es especialmente útil para capturar tests inestables que no fallan con la suficiente consistencia como para ser detectados por los reintentos, pero aún así causan fallos intermitentes en CI.

## Gestión de tests inestables {#managing-flaky-tests}

### Limpieza automática

La detección y la limpieza se ejecutan a través de una **alerta de automatización** en el proyecto. Cada proyecto recibe una automatización predeterminada "Detección de tests inestables" cuyo *disparador* marca un test como inestable y cuya *recuperación* elimina la marca una vez que el test ha pasado la ventana de recuperación configurada (predeterminada **14 días**) sin volver a dispararse. Edítala en **Configuración → Automatizaciones** para cambiar la ventana de recuperación, intercambiar las acciones de recuperación (por ejemplo, también sacar de cuarentena) o desactivar la recuperación por completo para que los tests permanezcan marcados como inestables hasta que los limpies manualmente.

### Gestión manual

También puedes marcar o desmarcar manualmente los tests como inestables desde la página de detalles del caso de test. Esto es útil cuando:
- Quieres reconocer un test inestable conocido mientras trabajas en una solución
- Un test fue marcado incorrectamente debido a problemas de infraestructura

## Poner en cuarentena los tests inestables {#quarantining}

La cuarentena aísla un test inestable para que no bloquee la CI mientras lo solucionas. Por defecto es una **acción manual** — pones en cuarentena, sacas de cuarentena y cambias de modo desde la página de detalles del caso de test en el dashboard — pero también puedes vincularlo a una **alerta de automatización** en **Configuración → Automatizaciones** para que un test se silencie automáticamente (o se omita) cuando supere un umbral de inestabilidad, y se saque de cuarentena cuando se recupere. Cada transición, manual o automatizada, se registra en el registro de auditoría del caso de test.

Un test en cuarentena está en uno de dos modos:

- **Silenciado**: el test sigue ejecutándose, pero el plugin establece `ignoreFailures = true` y solo hace fallar la build en fallos no puestos en cuarentena. Los fallos siguen alimentando el detector de tests inestables, por lo que puedes seguir observando el test sin romper la build. Elige esto para un test que estás investigando activamente.
- **Omitido**: el plugin filtra el test mediante `excludeTestsMatching` de Gradle, por lo que nunca se inicia. No produce nuevos resultados y desaparece del dashboard de tests inestables hasta que lo vuelvas a habilitar. Elige esto cuando el test esté roto, sea lento o tan persistentemente inestable que ejecutarlo sea simplemente un desperdicio de minutos de CI.

### Por qué los tests en cuarentena pueden aparecer como exitosos {#quarantined-passing}

- Los **tests silenciados** siguen ejecutándose. Un test silenciado que falla se registra como **fallido** en la ejecución del caso de test y se marca como inestable — el estado por test no se reescribe. Lo que se sobrescribe es la **ejecución general de tests**: si cada caso de test fallido en la ejecución está silenciado, la ejecución en su conjunto se informa como exitosa, por lo que los fallos silenciados no rompen la CI.
- Los **tests omitidos** no se ejecutan en absoluto, por lo que el dashboard sigue mostrando el estado de la última ejecución real del test — esa instantánea puede tener semanas de antigüedad.

### Habilitar la cuarentena {#enabling-quarantine}

La cuarentena se **habilita automáticamente en CI** (cuando la variable de entorno `CI` está establecida) y se deshabilita para builds locales. El plugin obtiene la lista de tests en cuarentena del servidor de Tuist antes de cada tarea de test; los tests silenciados se ejecutan normalmente y sus fallos se enmascaran, los tests omitidos se filtran.

Puedes controlar esto explícitamente en tu `settings.gradle.kts`:

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

Cuando `enabled` no está establecido, por defecto usa la autodetección: habilitado en CI, deshabilitado localmente.

## Pruebas de estrés para nuevos tests {#stress-testing-new-tests}

La puerta de estrés vuelve a ejecutar los casos de test que añade tu rama, varias veces cada uno en un proceso nuevo, e informa de los que resultan inestables. Verás un nuevo test inestable en la pull request que lo introdujo, no semanas después.

Un caso de test se considera nuevo cuando no se ha ejecutado en CI en los últimos 90 días en la rama predeterminada del proyecto, o en un commit que desde entonces se ha integrado en ella. Con una cola de merge, un caso de test que la cola ejecutó se conoce una vez que el commit de la cola se integra, y permanece como nuevo si la cola lo descarta. Los commits se emparejan a través del <.localized_link href="/guides/features/test-insights/gradle#git-history">historial de Git</.localized_link> que Tuist recopila en CI.

### Habilitarlo

La puerta está desactivada por defecto. Establece un modo:

- **`report`**: advierte sobre cada caso de test inestable. La ejecución aún termina con su propio resultado.
- **`enforce`**: un caso de test inestable hace fallar la ejecución, con el mismo código de salida que un test fallido.

Comienza con `report` durante un par de semanas para ver qué habría bloqueado `enforce`.

Decláralo en `settings.gradle.kts`, o establece `TUIST_TEST_STRESS_NEW_TESTS` para variar el modo por canal de CI:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

A diferencia de la cuarentena, la puerta no tiene un valor predeterminado consciente de CI. Sin `mode` establecido, no se ejecuta en ningún lugar.

### Cuántas veces se vuelve a ejecutar cada test

Depende de cuánto tiempo tardó el caso de test en la primera pasada:

| Primera pasada | Reejecuciones |
| --- | --- |
| Hasta 5s | 10 |
| Hasta 10s | 5 |
| Hasta 30s | 3 |
| Hasta 5min | 2 |
| Más de 5min | No se reejecuta |

Cada reejecución es una build de Gradle anidada filtrada para ese único caso de test, por lo que cada reejecución obtiene una JVM de test nueva. La pasada se detiene en 200 casos de test o 10 minutos, lo que ocurra primero, e indica qué límite alcanzó.

### Cuándo no se ejecuta la puerta

- La primera pasada ya falló. Corrige esos tests primero.
- El proyecto no tiene rama predeterminada, o nada se ha ejecutado aún en CI en ella.
- Más del 30% de los casos de test del proyecto parecen nuevos. Volver a ejecutar tantos llevaría más tiempo del que vale la pena. Espera esto en un proyecto que acaba de empezar a reportar a Tuist, o después de un renombrado que mueve muchos tests a la vez.

## Notificaciones de Slack {#slack-notifications}

Recibe notificaciones instantáneas cuando un test se vuelve inestable configurando <.localized_link href="/guides/integrations/slack#flaky-test-alerts">alertas de tests inestables</.localized_link> en tu integración de Slack.

## Consultar el estado inestable y en cuarentena {#querying}

### CLI

El árbol de comandos `tuist test case` expone todo lo que Tuist rastrea sobre un caso de test:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

Todos estos aceptan `--json` para scripting.

### API REST

Los mismos datos están disponibles vía HTTP — consulta los [endpoints de Casos de Test](https://tuist.dev/api/docs#tag/test-cases) en la referencia de la API para la lista completa de rutas, filtros y campos de respuesta. Para cambiar el estado de un caso de test (marcar o desmarcar como inestable, silenciar, omitir), envía `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` con `is_flaky` o `state`. El mismo cambio está disponible como `tuist test case update` y como la herramienta `update_test_case` del Model Context Protocol.
