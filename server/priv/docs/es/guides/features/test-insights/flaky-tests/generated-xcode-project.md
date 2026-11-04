---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Tests inestables · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Detecta, gestiona y aísla tests inestables en un proyecto de Xcode generado con Tuist."
}
---
# Proyecto de Xcode generado {#generated-xcode-project-flaky-tests}

> [!WARNING]
> **Requisitos**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Análisis de tests de Xcode</.localized_link> configurado (los esquemas autogenerados incluyen la post-acción `tuist inspect test`; los esquemas personalizados deben añadirla).

Los tests inestables son tests que producen resultados diferentes (pasar o fallar) al ejecutarse varias veces con el mismo código. Minan la confianza en tu suite de tests y hacen perder tiempo a los desarrolladores investigando fallos falsos. Tuist detecta automáticamente los tests inestables y te ayuda a seguirlos a lo largo del tiempo.

![Página de tests inestables](/images/guides/features/test-insights/flaky-tests-page.png)

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist detecta los tests inestables de dos maneras:

### Reintentos de tests {#test-retries}

Cuando ejecutas tests con funcionalidad de reintento, Tuist analiza los resultados de cada intento. Si un test falla en algunos intentos pero pasa en otros, se marca como inestable.

Pasa `-retry-tests-on-failure` o `-test-iterations` a través de `tuist test`:

```sh
tuist test --scheme MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![Detalle del caso de test inestable](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Detección entre ejecuciones {#cross-run-detection}

Incluso sin reintentos de tests, Tuist puede detectar tests inestables comparando resultados entre diferentes ejecuciones de CI en el mismo commit y el mismo esquema. Si un test pasa en una ejecución de CI pero falla en otra para el mismo commit y esquema, ambas ejecuciones se marcan como inestables.

El esquema forma parte de la clave de comparación porque el mismo test puede comportarse de manera determinista diferente entre esquemas — por ejemplo, un test de snapshot que solo es válido contra un destino de simulador específico, o un target de test que se compila con flags diferentes. Dos ejecuciones del mismo commit en esquemas diferentes se tratan como variantes de ejecución separadas y no se marcarán mutuamente como inestables.

Esto es especialmente útil para detectar tests inestables que no fallan con suficiente consistencia para ser capturados por los reintentos, pero que aún causan fallos intermitentes en CI.

## Gestión de tests inestables {#managing-flaky-tests}

### Limpieza automática

La detección y la limpieza se ejecutan mediante una **alerta de automatización** en el proyecto. Cada proyecto recibe una automatización predeterminada "Detección de tests inestables" cuyo *disparador* marca un test como inestable y cuya *recuperación* elimina la marca una vez que el test ha pasado la ventana de recuperación configurada (por defecto **14 días**) sin volver a dispararse. Edítala en **Configuración → Automatizaciones** para cambiar la ventana de recuperación, intercambiar las acciones de recuperación (p. ej., también sacar de cuarentena) o desactivar la recuperación por completo para que los tests permanezcan marcados como inestables hasta que los limpies manualmente.

### Gestión manual

También puedes marcar o desmarcar manualmente los tests como inestables desde la página de detalle del caso de test. Esto es útil cuando:
- Quieres reconocer un test inestable conocido mientras trabajas en una solución
- Un test se marcó incorrectamente debido a problemas de infraestructura

## Poner en cuarentena los tests inestables {#quarantining}

La cuarentena aísla un test inestable para que no bloquee la CI mientras lo arreglas. Por defecto es una **acción manual** — pones en cuarentena, sacas de cuarentena y cambias de modo desde la página de detalle del caso de test en el dashboard — pero también puedes integrarlo en una **alerta de automatización** en **Configuración → Automatizaciones** para que un test se silencie automáticamente (o se omita) cuando supere un umbral de inestabilidad, y se saque de cuarentena cuando se recupere. Cada transición, manual o automatizada, se registra en el log de auditoría del caso de test.

Por defecto, la recuperación espera hasta que la condición del disparador ya no se cumpla, por lo que un test permanece en cuarentena hasta que sus antiguas ejecuciones inestables salgan de la ventana del disparador. Para recuperarse antes, establece **Recuperar cuando** en **Sin nuevas ejecuciones inestables**: el test se recupera una vez que pasa la ventana de recuperación (días o ejecuciones) sin una nueva ejecución inestable, cada nueva ejecución inestable reinicia esa espera y, tras la recuperación, solo una nueva ejecución inestable lo vuelve a poner en cuarentena.

Un test en cuarentena está en uno de dos modos:

- **Silenciado**: el test sigue ejecutándose, pero `tuist test` enmascara el fallo. Los fallos siguen alimentando el detector de tests inestables, por lo que puedes seguir vigilando el test sin romper la compilación. Elige este modo para un test que estás investigando activamente.
- **Omitido**: xcodebuild recibe `-skip-testing <identifier>`, por lo que el test nunca comienza. No produce nuevos resultados y desaparece del dashboard de tests inestables hasta que lo vuelvas a habilitar. Elige esto cuando el test esté roto, sea lento o tan persistentemente inestable que ejecutarlo sea solo un desperdicio de minutos de CI.

### Por qué los tests en cuarentena pueden aparecer como pasados {#quarantined-passing}

- **Tests silenciados** todavía se ejecutan. Un test silenciado que falla se registra como **fallido** en la ejecución del caso de test y se marca como inestable — el estado por test no se reescribe. Lo que se sobrescribe es la **ejecución de tests completa**: si todos los casos de test fallidos en la ejecución están silenciados, la ejecución en su conjunto se informa como pasada, por lo que los fallos silenciados no rompen la CI.
- **Tests omitidos** no se ejecutan en absoluto, por lo que el dashboard sigue mostrando el estado de la última ejecución real del test — esa instantánea puede tener semanas de antigüedad.

### Ejecutar tests {#running-tests}

`tuist test` respeta ambos modos automáticamente:

```sh
tuist test
```

Los tests omitidos se pasan a xcodebuild como `-skip-testing` y nunca comienzan. Los tests silenciados se ejecutan normalmente; si fallan, el fallo se enmascara en el estado de compilación resultante.

Para omitir por completo la cuarentena y ejecutar todo, incluidos los tests silenciados y omitidos:

```sh
tuist test --skip-quarantine
```

## Pruebas de estrés para nuevos tests {#stress-testing-new-tests}

La puerta de estrés vuelve a ejecutar los casos de test que añade tu rama, varias veces cada uno en un proceso nuevo, e informa de los que resultan inestables. Verás un nuevo test inestable en la pull request que lo introdujo, no semanas después.

Un caso de test se considera nuevo cuando no se ha ejecutado en CI en los últimos 90 días en la rama predeterminada del proyecto, o en un commit que haya aterrizado desde entonces en ella. Con una cola de merge, un caso de test que la cola ejecutó se conoce una vez que el commit de la cola aterriza, y permanece como nuevo si la cola lo descarta. Los commits se emparejan a través del <.localized_link href="/guides/features/test-insights/xcode#git-history">historial de Git</.localized_link> que Tuist recopila en CI.

### Habilitarlo

La puerta está desactivada por defecto. Establece un modo:

- **`report`**: avisa sobre cada caso de test inestable. La ejecución sigue terminando con su propio resultado.
- **`enforce`**: un caso de test inestable hace fallar la ejecución, con el mismo código de salida que un test fallido.

En ambos modos, <.localized_link href="/guides/features/selective-testing/generated-xcode-project">los tests selectivos</.localized_link> no omiten un target de test con un nuevo caso de test inestable en la siguiente ejecución. El target se ejecuta de nuevo y la puerta somete el caso de test a estrés otra vez, hasta que pasa todas sus reejecuciones.

Comienza con `report` durante un par de semanas para ver qué habría bloqueado `enforce`.

Pásalo antes de los argumentos de paso, o establece `TUIST_TEST_STRESS_NEW_TESTS` para variar el modo por canal de CI:

```sh
tuist test --stress-new-tests report
```

### Cuántas veces se reejecuta cada test

Depende de cuánto tardó el caso de test en la primera pasada:

| Primera pasada | Reejecuciones |
| --- | --- |
| Hasta 5 s | 10 |
| Hasta 10 s | 5 |
| Hasta 30 s | 3 |
| Hasta 5 min | 2 |
| Más de 5 min | No se reejecuta |

Las reejecuciones reutilizan lo que construyó la primera pasada. La pasada se detiene al llegar a 200 casos de test o 10 minutos, lo que ocurra primero, e indica qué límite alcanzó.

### Cuándo no se ejecuta la puerta

- La primera pasada ya falló. Arregla esos tests primero.
- El proyecto no tiene rama predeterminada, o nada se ha ejecutado aún en CI en ella.
- Más del 30 % de los casos de test del proyecto parecen nuevos. Volver a ejecutar tantos llevaría más tiempo del que vale la pena. Espera esto en un proyecto que acaba de empezar a reportar a Tuist, o después de un renombrado que mueve muchos tests a la vez.

## Notificaciones de Slack {#slack-notifications}

Recibe notificaciones al instante cuando un test se vuelve inestable configurando <.localized_link href="/guides/integrations/slack#flaky-test-alerts">alertas de tests inestables</.localized_link> en tu integración de Slack.

## Consultar el estado de inestabilidad y cuarentena {#querying}

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

Los mismos datos están disponibles por HTTP; consulta los [endpoints de Casos de Test](https://tuist.dev/api/docs#tag/test-cases) en la referencia de la API para la lista completa de rutas, filtros y campos de respuesta. Para cambiar el estado de un caso de test (marcar o desmarcar como inestable, silenciar, omitir), envía `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` con `is_flaky` o `state`. El mismo cambio está disponible como `tuist test case update` y como la herramienta `update_test_case` del Model Context Protocol.
