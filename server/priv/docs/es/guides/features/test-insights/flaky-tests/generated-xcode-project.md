---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Flaky tests · Test insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in a Tuist-generated Xcode project."
}
---
# Proyecto de Xcode generado {#generated-xcode-project-flaky-tests}

> [!WARNING]
> **Requisitos**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Insights de tests de Xcode</.localized_link> configurado (los esquemas generados automáticamente incluyen la post-acción `tuist inspect test`; los esquemas personalizados necesitan añadirla).

Los tests flaky son tests que producen resultados diferentes (éxito o fallo) cuando se ejecutan varias veces con el mismo código. Minan la confianza en tu suite de tests y hacen perder tiempo a los desarrolladores investigando fallos falsos. Tuist detecta automáticamente los tests flaky y te ayuda a rastrearlos a lo largo del tiempo.

![Página de Tests Flaky](/images/guides/features/test-insights/flaky-tests-page.png)

## Cómo funciona la detección de flaky {#how-it-works}

Tuist detecta los tests flaky de dos maneras:

### Reintentos de tests {#test-retries}

Cuando ejecutas tests con funcionalidad de reintento, Tuist analiza los resultados de cada intento. Si un test falla en algunos intentos pero tiene éxito en otros, se marca como flaky.

Pasa `-retry-tests-on-failure` o `-test-iterations` a través de `tuist test`:

```sh
tuist test --scheme MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![Detalle del caso de test flaky](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Detección entre ejecuciones {#cross-run-detection}

Incluso sin reintentos de tests, Tuist puede detectar tests flaky comparando resultados entre diferentes ejecuciones de CI en el mismo commit y el mismo esquema. Si un test tiene éxito en una ejecución de CI pero falla en otra para el mismo commit y esquema, ambas ejecuciones se marcan como flaky.

El esquema forma parte de la clave de comparación porque el mismo test puede comportarse de manera determinista diferente entre esquemas — por ejemplo, un test de snapshot que solo es válido contra un destino de simulador específico, o un target de test que se compila con flags diferentes. Dos ejecuciones del mismo commit en esquemas diferentes se tratan como variantes de ejecución separadas y no se marcarán mutuamente como flaky.

Esto es particularmente útil para capturar tests flaky que no fallan con suficiente consistencia como para ser detectados por los reintentos, pero aún así causan fallos intermitentes en CI.

## Gestión de tests flaky {#managing-flaky-tests}

### Limpieza automática

La detección y limpieza se ejecutan a través de una **alerta de automatización** en el proyecto. Cada proyecto recibe una automatización predeterminada "Detección de tests flaky" cuyo *disparador* marca un test como flaky y cuya *recuperación* limpia la marca una vez que el test ha pasado la ventana de recuperación configurada (por defecto **14 días**) sin volver a dispararse. Edítala bajo **Ajustes → Automatizaciones** para cambiar la ventana de recuperación, intercambiar las acciones de recuperación (p. ej., también sacar de cuarentena) o desactivar la recuperación por completo para que los tests permanezcan marcados como flaky hasta que los limpies manualmente.

### Gestión manual

También puedes marcar o desmarcar manualmente los tests como flaky desde la página de detalle del caso de test. Esto es útil cuando:
- Quieres reconocer un test flaky conocido mientras trabajas en una corrección
- Un test fue marcado incorrectamente debido a problemas de infraestructura

## Poner en cuarentena los tests flaky {#quarantining}

La cuarentena aísla un test flaky para que no bloquee CI mientras lo corriges. Por defecto es una **acción manual** — pones en cuarentena, sacas de cuarentena y cambias de modo desde la página de detalle del caso de test en el dashboard — pero también puedes integrarlo en una **alerta de automatización** bajo **Ajustes → Automatizaciones** para que un test se silencie automáticamente (o se omita) cuando supere un umbral de flakiness, y se saque de cuarentena cuando se recupere. Cada transición, manual o automatizada, se registra en el log de auditoría del caso de test.

Un test en cuarentena está en uno de dos modos:

- **Silenciado**: el test sigue ejecutándose, pero `tuist test` enmascara el fallo. Los fallos siguen alimentando el detector de tests flaky, por lo que puedes seguir observando el test sin romper la build. Elige esto para un test que estás investigando activamente.
- **Omitido**: xcodebuild recibe `-skip-testing <identifier>`, por lo que el test nunca comienza. No produce nuevos resultados y desaparece del dashboard de tests flaky hasta que lo vuelvas a habilitar. Elige esto cuando el test esté roto, sea lento o tan persistentemente flaky que ejecutarlo sea simplemente un desperdicio de minutos de CI.

### Por qué los tests en cuarentena pueden aparecer como exitosos {#quarantined-passing}

- **Los tests silenciados** siguen ejecutándose. Un test silenciado que falla se registra como **fallido** en la ejecución del caso de test y se marca como flaky — el estado por test no se reescribe. Lo que se sobrescribe es la **ejecución general de tests**: si cada caso de test fallido en la ejecución está silenciado, la ejecución en su conjunto se informa como exitosa, por lo que los fallos silenciados no rompen CI.
- **Los tests omitidos** no se ejecutan en absoluto, por lo que el dashboard sigue mostrando el estado de la última ejecución real del test — esa instantánea puede tener semanas de antigüedad.

### Ejecución de tests {#running-tests}

`tuist test` respeta ambos modos automáticamente:

```sh
tuist test
```

Los tests omitidos se pasan a xcodebuild como `-skip-testing` y nunca comienzan. Los tests silenciados se ejecutan normalmente; si fallan, el fallo se enmascara en el estado de build resultante.

Para omitir completamente la cuarentena y ejecutar todo, incluidos los tests silenciados y omitidos:

```sh
tuist test --skip-quarantine
```

## Pruebas de estrés para nuevos tests {#stress-testing-new-tests}

La puerta de estrés vuelve a ejecutar los casos de test que añade tu rama, varias veces cada uno en un proceso nuevo, e informa de los que resultan ser flaky. Verás un nuevo test flaky en la pull request que lo introdujo, no semanas después.

Un caso de test se considera nuevo cuando no se ha ejecutado en CI en los últimos 90 días en la rama predeterminada del proyecto, o en un commit que haya aterrizado desde entonces en ella. Con una cola de merge, un caso de test que la cola ejecutó se conoce una vez que el commit de la cola aterriza, y permanece como nuevo si la cola lo descarta. Los commits se emparejan a través del <.localized_link href="/guides/features/test-insights/xcode#git-history">historial de Git</.localized_link> que Tuist recopila en CI.

### Habilitación

La puerta está desactivada por defecto. Establece un modo:

- **`report`**: advierte sobre cada caso de test flaky. La ejecución aún termina con su propio resultado.
- **`enforce`**: un caso de test flaky hace fallar la ejecución, con el mismo código de salida que un test fallido.

En ambos modos, <.localized_link href="/guides/features/selective-testing/generated-xcode-project">selective testing</.localized_link> no omite un target de test con un nuevo caso de test flaky en la siguiente ejecución. El target se ejecuta de nuevo y la puerta somete a estrés el caso de test otra vez, hasta que supera todas sus reejecuciones.

Comienza con `report` durante un par de semanas para ver qué habría bloqueado `enforce`.

Pásalo antes de los argumentos de paso directo, o establece `TUIST_TEST_STRESS_NEW_TESTS` para variar el modo por canal de CI:

```sh
tuist test --stress-new-tests report
```

### Cuántas veces se reejecuta cada test

Depende de cuánto tardó el caso de test en la primera pasada:

| Primera pasada | Reejecuciones |
| --- | --- |
| Hasta 5s | 10 |
| Hasta 10s | 5 |
| Hasta 30s | 3 |
| Hasta 5min | 2 |
| Más de 5min | No se reejecuta |

Las reejecuciones reutilizan lo que construyó la primera pasada. La pasada se detiene en 200 casos de test o 10 minutos, lo que ocurra primero, e indica qué límite alcanzó.

### Cuándo no se ejecuta la puerta

- La primera pasada ya falló. Corrige esos tests primero.
- El proyecto no tiene una rama predeterminada, o aún no se ha ejecutado nada en CI sobre ella.
- Más del 30% de los casos de test del proyecto parecen nuevos. Volver a ejecutar tantos llevaría más tiempo del que vale la pena. Espera esto en un proyecto que acaba de empezar a reportar a Tuist, o después de un renombrado que mueve muchos tests a la vez.

## Notificaciones de Slack {#slack-notifications}

Recibe notificaciones al instante cuando un test se vuelve flaky configurando <.localized_link href="/guides/integrations/slack#flaky-test-alerts">alertas de tests flaky</.localized_link> en tu integración de Slack.

## Consulta del estado flaky y en cuarentena {#querying}

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

### REST API

Los mismos datos están disponibles mediante HTTP — consulta los [endpoints de Test Cases](https://tuist.dev/api/docs#tag/test-cases) en la referencia de la API para la lista completa de rutas, filtros y campos de respuesta. Para cambiar el estado de un caso de test (marcar o desmarcar como flaky, silenciar, omitir), envía `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` con `is_flaky` o `state`. El mismo cambio está disponible como `tuist test case update` y como la herramienta `update_test_case` Model Context Protocol.
