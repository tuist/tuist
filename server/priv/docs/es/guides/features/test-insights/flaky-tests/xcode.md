---
{
  "title": "Xcode Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Xcode projects with Tuist."
}
---
# Tests inestables de Xcode {#xcode-flaky-tests}

> [!WARNING]
> **Requisitos**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Insights de tests de Xcode</.localized_link> configurado. Tuist detecta tests inestables a partir de los eventos de insights de tests subidos por cada ejecución de tests.

Los tests inestables son tests que producen resultados diferentes (éxito o fallo) cuando se ejecutan varias veces con el mismo código. Minan la confianza en tu suite de tests y hacen perder tiempo a los desarrolladores investigando fallos falsos. Tuist detecta automáticamente los tests inestables y te ayuda a seguirlos a lo largo del tiempo.

![Página de Tests Inestables](/images/guides/features/test-insights/flaky-tests-page.png)

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist detecta tests inestables de dos maneras:

### Reintentos de tests {#test-retries}

Cuando ejecutas tests con funcionalidad de reintento, Tuist analiza los resultados de cada intento. Si un test falla en algunos intentos pero tiene éxito en otros, se marca como inestable.

Pasa `-retry-tests-on-failure` o `-test-iterations` a través de `tuist xcodebuild test`:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![Detalle del caso de test inestable](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Detección entre ejecuciones {#cross-run-detection}

Incluso sin reintentos de tests, Tuist puede detectar tests inestables comparando resultados entre diferentes ejecuciones de CI en el mismo commit, esquema y destino informado (nombre del dispositivo, plataforma y versión del sistema operativo). Si un test tiene éxito en una ejecución de CI coincidente pero falla en otra, la ejecución fallida se marca como inestable. Esto funciona independientemente de qué resultado llegue primero.

El mismo test puede comportarse de manera consistentemente diferente entre esquemas o destinos. Por ejemplo, tener éxito en iOS 26 y fallar en iOS 27 no establece inestabilidad. Los resultados de diferentes esquemas, dispositivos, plataformas o versiones del sistema operativo no se marcan entre sí como inestables.

Los resultados sin un destino atribuible se comparan con otros resultados no atribuidos, por separado de los resultados con un destino conocido. Esto incluye informes con metadatos de destino faltantes o incompletos e informes que contienen múltiples destinos distintos, porque los resultados individuales de los tests aún no pueden atribuirse a un destino. Las diferencias entre entornos en este grupo aún pueden producir clasificaciones falsas de inestabilidad. La detección basada en reintentos sigue aplicándose. Las clasificaciones históricas existentes de inestabilidad permanecen sin cambios.

Esto es particularmente útil para capturar tests inestables que no fallan con suficiente consistencia para ser detectados por reintentos, pero aún causan fallos intermitentes en CI.

## Gestión de tests inestables {#managing-flaky-tests}

### Limpieza automática

La detección y limpieza se ejecutan mediante una **alerta de automatización** en el proyecto. Cada proyecto recibe una automatización predeterminada "Detección de tests inestables" cuyo *disparador* marca un test como inestable y cuya *recuperación* elimina la marca una vez que el test ha pasado la ventana de recuperación configurada (por defecto **14 días**) sin volver a dispararse. Edítala en **Configuración → Automatizaciones** para cambiar la ventana de recuperación, intercambiar las acciones de recuperación (por ejemplo, también sacar de cuarentena) o desactivar la recuperación por completo para que los tests permanezcan marcados como inestables hasta que los limpies manualmente.

### Gestión manual

También puedes marcar o desmarcar manualmente los tests como inestables desde la página de detalles del caso de test. Esto es útil cuando:
- Quieres reconocer un test inestable conocido mientras trabajas en una solución
- Un test fue marcado incorrectamente debido a problemas de infraestructura

## Poner en cuarentena tests inestables {#quarantining}

La cuarentena aísla un test inestable para que no bloquee CI mientras lo solucionas. Por defecto es una **acción manual**: pones en cuarentena, sacas de cuarentena y cambias de modo desde la página de detalles del caso de test en el dashboard, pero también puedes vincularlo a una **alerta de automatización** en **Configuración → Automatizaciones** para que un test se silencie automáticamente (o se omita) cuando supera un umbral de inestabilidad, y se saque de cuarentena cuando se recupere. Cada transición, manual o automatizada, se registra en el registro de auditoría del caso de test.

Un test en cuarentena está en uno de dos modos:

- **Silenciado**: el test sigue ejecutándose, pero `tuist xcodebuild test` enmascara el fallo. Los fallos siguen alimentando el detector de tests inestables, por lo que puedes seguir observando el test sin romper la compilación. Elige esto para un test que estás investigando activamente.
- **Omitido**: xcodebuild recibe `-skip-testing <identifier>`, por lo que el test nunca comienza. No produce nuevos resultados y desaparece del dashboard de tests inestables hasta que lo vuelvas a habilitar. Elige esto cuando el test esté roto, sea lento o sea tan persistentemente inestable que ejecutarlo solo desperdicie minutos de CI.

### Por qué los tests en cuarentena pueden aparecer como exitosos {#quarantined-passing}

- **Los tests silenciados** aún se ejecutan. Un test silenciado que falla se registra como **fallido** en la ejecución del caso de test y se marca como inestable; el estado por test no se reescribe. Lo que se sobrescribe es la **ejecución de tests completa**: si cada caso de test fallido en la ejecución está silenciado, la ejecución en su conjunto se informa como exitosa, por lo que los fallos silenciados no rompen CI.
- **Los tests omitidos** no se ejecutan en absoluto, por lo que el dashboard sigue mostrando el estado de la última ejecución real del test; esa instantánea puede tener semanas de antigüedad.

### Ejecución de tests {#running-tests}

`tuist xcodebuild test` es un envoltorio de paso directo que respeta ambos modos automáticamente. Úsalo de la misma manera que llamarías a xcodebuild:

```sh
tuist xcodebuild test -scheme MyScheme
```

Los tests omitidos se añaden a tu invocación de xcodebuild como `-skip-testing <identifier>` y nunca comienzan. Los tests silenciados se ejecutan normalmente; si fallan, el fallo se enmascara en el estado de compilación resultante.

#### Omitir la cuarentena

`tuist xcodebuild test` acepta `--skip-quarantine` para ejecutar todo, incluidos los tests silenciados y omitidos:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### Llamar a xcodebuild directamente

Si no puedes pasar por `tuist xcodebuild test`, expande los tests en cuarentena en argumentos `-skip-testing` tú mismo con `tuist test case list`:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

Este es el valor predeterminado seguro fuera de `tuist xcodebuild test`: el enmascaramiento de fallos para tests silenciados solo ocurre cuando pasas por ese comando, por lo que omitir ambos modos evita fallos espurios de CI. Si necesitas un control más fino, pasa por `tuist xcodebuild test` en su lugar.

## Pruebas de estrés para nuevos tests {#stress-testing-new-tests}

La puerta de estrés vuelve a ejecutar los casos de test que añade tu rama, varias veces cada uno en un proceso nuevo, e informa de los que resultan inestables. Verás un nuevo test inestable en la pull request que lo introdujo, no semanas después.

Un caso de test se considera nuevo cuando no se ha ejecutado en CI en los últimos 90 días en la rama predeterminada del proyecto, o en un commit que desde entonces se haya fusionado en ella. Con una cola de fusión, un caso de test que la cola ejecutó se conoce una vez que el commit de la cola se fusiona, y sigue siendo nuevo si la cola lo descarta. Los commits se emparejan a través del <.localized_link href="/guides/features/test-insights/xcode#git-history">historial de Git</.localized_link> que Tuist recopila en CI.

### Habilitarlo

La puerta está desactivada por defecto. Establece un modo:

- **`report`**: advierte sobre cada caso de test inestable. La ejecución finaliza según su propio resultado.
- **`enforce`**: un caso de test inestable hace fallar la ejecución, con el mismo código de salida que un test fallido.

Comienza con `report` durante un par de semanas para ver qué habría bloqueado `enforce`.

Pásalo antes de los argumentos de paso directo, o establece `TUIST_TEST_STRESS_NEW_TESTS` para variar el modo por canal de CI:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

### Cuántas veces se vuelve a ejecutar cada test

Depende de cuánto tiempo tardó el caso de test en la primera pasada:

| Primera pasada | Reejecuciones |
| --- | --- |
| Hasta 5 s | 10 |
| Hasta 10 s | 5 |
| Hasta 30 s | 3 |
| Hasta 5 min | 2 |
| Más de 5 min | No se reejecuta |

Las reejecuciones reutilizan lo que construyó la primera pasada. La pasada se detiene en 200 casos de test o 10 minutos, lo que ocurra primero, e indica qué límite alcanzó.

### Cuándo no se ejecuta la puerta

- La primera pasada ya falló. Arregla esos tests primero.
- El proyecto no tiene rama predeterminada, o nada se ha ejecutado aún en CI en ella.
- Más del 30% de los casos de test del proyecto parecen nuevos. Volver a ejecutar tantos llevaría más tiempo del que vale la pena. Espera esto en un proyecto que acaba de empezar a informar a Tuist, o después de un renombrado que mueve muchos tests a la vez.

## Notificaciones de Slack {#slack-notifications}

Recibe notificaciones instantáneas cuando un test se vuelve inestable configurando <.localized_link href="/guides/integrations/slack#flaky-test-alerts">alertas de tests inestables</.localized_link> en tu integración de Slack.

## Consulta del estado inestable y en cuarentena {#querying}

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

Los mismos datos están disponibles a través de HTTP: consulta los [endpoints de Casos de Test](https://tuist.dev/api/docs#tag/test-cases) en la referencia de la API para la lista completa de rutas, filtros y campos de respuesta. Para cambiar el estado de un caso de test (marcar o desmarcar como inestable, silenciar, omitir), envía `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` con `is_flaky` o `state`. El mismo cambio está disponible como `tuist test case update` y como la herramienta `update_test_case` del Protocolo de Contexto de Modelo.
