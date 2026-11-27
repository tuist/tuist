---
{
  "title": "¿Qué es un test flaky? Causas, detección y soluciones",
  "titleTemplate": ":title · Tuist",
  "description": "Un test flaky pasa y falla con el mismo código. Conoce las causas más comunes, cómo funciona la detección de tests flaky en Xcode, Gradle y Bazel, y cómo medir la inestabilidad."
}
---
# ¿Qué es un test inestable? {#what-is-a-flaky-test}

Un test inestable es un test automatizado que tanto pasa como falla cuando se ejecuta contra el mismo código, sin que haya cambiado nada en el código bajo prueba ni en el propio test. Su resultado depende de algo que el test no controla, como la temporización, el orden en que se ejecutan los tests, el estado dejado por otro test, la máquina en la que se ejecuta o un servicio al que llama a través de la red. Por lo tanto, un fallo inestable no aporta información fiable sobre el cambio que se está probando, y eso es lo que hace que los tests inestables sean costosos: cada resultado en rojo debe investigarse o reintentarse antes de que alguien pueda confiar en él.

La inestabilidad es común a cualquier escala. Google informó de que aproximadamente el 1,5 % de todas sus ejecuciones de tests producían un resultado inestable y que casi el 16 % de sus tests mostraban algún nivel de inestabilidad ([Flaky Tests at Google and How We Mitigate Them](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html), 2016).

## Cómo se manifiestan los tests inestables {#how-flaky-tests-show-up}

Solo se sabe que un test es inestable una vez que ha producido ambos resultados para la misma entrada. En la práctica, esa evidencia proviene de uno de tres lugares:

- **Reintentos dentro de una ejecución.** Un test falla, el runner lo reintenta y el reintento pasa. Esta es la señal más económica y la mayoría de los runners de tests pueden generarla.
- **Ejecuciones discordantes del mismo commit.** Dos ejecuciones de CI del mismo commit y configuración informan de resultados diferentes para un test, por ejemplo, una ejecución en la pull request y una nueva ejecución después de que alguien haga clic en reintentar.
- **Repetición deliberada.** Un test se ejecuta muchas veces seguidas, a propósito, para ver si alguna vez falla. Así es como los equipos confirman una inestabilidad sospechada o comprueban que un nuevo test es estable antes de fusionarlo.

Los resultados solo cuentan como evidencia de inestabilidad cuando todo lo importante es igual: el commit, la configuración de compilación, el dispositivo o simulador, la versión del sistema operativo y la cadena de herramientas. Un test que falla en iOS 17 y pasa en iOS 18 puede tener un error real y determinista en uno de ellos.

## Cómo funciona la detección de tests inestables según el sistema de compilación {#how-it-works-per-build-system}

Cada cadena de herramientas puede reintentar y repetir tests, pero registran e informan de los resultados de manera diferente.

### Xcode {#xcode}

`xcodebuild` y los planes de test admiten la repetición de tests. `-retry-tests-on-failure` vuelve a ejecutar un test fallido, `-test-iterations <n>` establece cuántos intentos se permiten y `-run-tests-until-failure` repite un test hasta que falla, lo cual es útil para reproducir una inestabilidad sospechada. Los planes de test exponen las mismas opciones que un modo de repetición de tests, además de una opción para ejecutar los tests en orden aleatorio, lo que revela dependencias de orden ocultas.

Cada intento se almacena en el bundle `.xcresult`, por lo que un test que falló y luego pasó en el reintento es visible allí. Xcode no mantiene el historial entre ejecuciones, por lo que detectar inestabilidades que nunca se reintentan en la misma ejecución requiere comparar bundles de resultados de diferentes ejecuciones del mismo commit.

### Gradle {#gradle}

La tarea `Test` de Gradle no reintenta los tests fallidos por sí misma. El [plugin Test Retry](https://github.com/gradle/test-retry-gradle-plugin) (`org.gradle.test-retry`) añade un bloque `retry` a las tareas `Test`, con opciones como `maxRetries` y `failOnPassedAfterRetry`. Un test que falla y luego pasa aparece con ambos intentos en los informes de tests y en el XML de JUnit. Los frameworks de tests añaden sus propias herramientas de repetición, como `@RepeatedTest` de JUnit 5.

La caché de compilación de Gradle también puede ocultar la inestabilidad: una tarea `Test` cacheable con entradas sin cambios se restaura desde la caché en lugar de ejecutarse, por lo que un test que pasó una vez sigue pasando sin ejecutarse. Cuando midas la inestabilidad, fuerza la ejecución de los tests con `--rerun-tasks` o ejecutando la tarea `Test` con la caché de compilación desactivada.

### Bazel {#bazel}

Bazel tiene soporte integrado. Marcar un objetivo de test con `flaky = True` hace que Bazel lo ejecute hasta tres veces y solo falle si todos los intentos fallan. La bandera `--flaky_test_attempts` establece el número de intentos sin cambiar el objetivo, y el resultado del objetivo se informa como `FLAKY` cuando pasa después de un intento fallido. Para medir la inestabilidad a propósito, `--runs_per_test=<n>` ejecuta un test muchas veces y `--runs_per_test_detects_flakes` informa de un shard como `FLAKY` cuando al menos una ejecución pasa y otra falla.

Bazel almacena en caché los resultados de los tests de la misma manera que almacena en caché los artefactos de compilación. Un test que pasó con las mismas entradas se informa como `(cached) PASSED` sin volver a ejecutarse, tanto localmente como desde una caché remota. Usa `--cache_test_results=no` (o `--nocache_test_results`) cuando necesites ejecuciones frescas. La documentación de Bazel también desaconseja depender de `flaky = True`, porque oculta permanentemente los fallos que reintenta.

### Otros runners de tests {#other-test-runners}

El mismo patrón existe en casi todas partes: pytest tiene el plugin `pytest-rerunfailures`, Jest tiene `jest.retryTimes()` y ExUnit de Elixir tiene `mix test --repeat-until-failure` e imprime la semilla aleatoria que utilizó para que un fallo dependiente del orden pueda reproducirse con `--seed`.

## Causas comunes de tests inestables {#common-causes}

Un estudio empírico de tests inestables en proyectos de código abierto ([Luo et al., FSE 2014](https://doi.org/10.1145/2635868.2635920)) encontró que la espera asíncrona, la concurrencia y la dependencia del orden de los tests son las causas raíz más comunes. La lista siguiente cubre esas y otras causas con las que los equipos se encuentran con más frecuencia.

- **Esperas asíncronas y sleeps fijos.** El test espera un tiempo fijo para que termine el trabajo, como `sleep(1)` o una expectativa con un timeout corto, y el trabajo a veces tarda más, especialmente en una máquina de CI cargada. Espera a la condición en sí, con un límite superior generoso.
- **Concurrencia.** Dos hilos o tareas compiten por datos compartidos, o el test realiza aserciones antes de que complete una operación en segundo plano. Estos fallos suelen depender del número de CPU y de la carga, por lo que aparecen en CI y no en un portátil rápido.
- **Dependencia del orden de los tests y estado compartido.** Un test depende del estado que creó otro test u olvidó limpiar: un singleton, una fila de base de datos, un archivo en disco, `UserDefaults`, una variable de entorno o un global mockeado. Ejecutar los tests en orden aleatorio o en paralelo lo expone.
- **Hora y fechas.** Los tests que utilizan el reloj real fallan a medianoche, al final de un mes, durante los cambios de horario de verano o en otra zona horaria. Inyecta un reloj en su lugar.
- **Aleatoriedad sin semilla y colecciones sin orden.** Datos aleatorios sin una semilla registrada, o aserciones que dependen del orden de iteración de un mapa hash o un conjunto.
- **Red y servicios externos.** Las llamadas a APIs reales, registros de paquetes o entornos de staging compartidos fallan cuando esos servicios son lentos o no están disponibles. Simúlalos en el límite y mantén un número reducido de tests de integración explícitos.
- **Presión de recursos y estado del entorno.** Máquinas lentas o sobrecargadas, un simulador o emulador que no se ha reiniciado, un disco lleno o un puerto que ya usa otro trabajo. Cuando muchos tests no relacionados fallan a la vez, sospecha del entorno antes que de los tests.
- **Tests de UI.** Los tests end-to-end y de UI combinan la mayoría de las causas anteriores con animaciones, tiempos de renderizado y diálogos del sistema, por lo que son inestables con más frecuencia que los tests unitarios.

Un test que falla de forma consistente tras un cambio no es inestable; es una regresión. La etiqueta de inestable debe reservarse para tests que han producido ambos resultados sobre el mismo código.

## Corregir, reintentar y poner en cuarentena {#fixing-retrying-and-quarantining}

Los equipos suelen combinar tres respuestas, y ayuda mantenerlas separadas:

- **Corregir** la causa. Esta es la única respuesta que restaura el valor del test. Los intentos registrados, los mensajes de error y las condiciones de cada ejecución fallida son la evidencia que señala la causa.
- **Reintentar** para mantener las pipelines en movimiento. Los reintentos son una señal de detección útil, pero los reintentos generalizados ocultan el problema y añaden tiempo de máquina a cada ejecución fallida. Un reintento que pasa debe seguir registrándose como resultado inestable, no descartarse en silencio.
- **Poner en cuarentena** un test inestable conocido para que deje de bloquear merges mientras se corrige. Un test en cuarentena sigue ejecutándose con sus fallos ignorados (silenciado), lo que sigue generando evidencia, o no se ejecuta en absoluto (omitido), lo que elimina su cobertura. La cuarentena necesita un responsable y una condición de salida, o los tests en cuarentena se acumulan y la cobertura disminuye silenciosamente.

## Cómo medir la inestabilidad {#how-to-measure-flakiness}

Rastrea la inestabilidad por test, no solo por pipeline:

- **Tasa de inestabilidad.** La proporción de ejecuciones de un test que produjeron un resultado inestable: un fallo seguido de un reintento exitoso, o un resultado que discrepa con otra ejecución del mismo commit y configuración.
- **Impacto.** Cuántas pipelines, pull requests o entradas en la cola de merge bloqueó o ralentizó un test, y cuánto tiempo de máquina consumieron sus reintentos. Un test con una tasa de inestabilidad baja que se ejecuta en cada pipeline puede costar más que un test muy inestable que rara vez se ejecuta.
- **Tendencia.** Si se están introduciendo nuevos tests inestables más rápido de lo que se corrigen los antiguos. Repetir varias veces los tests nuevos o modificados antes de que se fusionen detecta muchas inestabilidades en el origen.

Confirmar que un test es estable requiere más ejecuciones de las que sugiere la intuición. Si un test falla con probabilidad *p* en cada ejecución, la probabilidad de ver al menos un fallo en *n* ejecuciones es 1 − (1 − p)ⁿ. Para un test que falla el 1% de las veces, 10 ejecuciones lo detectan solo alrededor del 10% de las veces, y hacen falta unas 300 ejecuciones para detectarlo con un 95% de confianza. Un puñado de reruns verdes es una evidencia débil de que una corrección funcionó.

## Cuándo no vale la pena {#when-it-isnt-worth-it}

No todo test inestable merece una investigación, y no todo equipo necesita herramientas para tests inestables:

- **Tests de bajo valor.** Si un test inestable duplica la cobertura que ya proporcionan otros tests, eliminarlo puede ser la corrección adecuada. Un test en el que nadie confía no aporta cobertura de todos modos.
- **Problemas de infraestructura.** Cuando los fallos se concentran en una máquina, una imagen de runner o una hora del día concretas, corregir el entorno es más barato que arreglar los tests uno por uno.
- **Suites pequeñas y rápidas.** Para un equipo pequeño con una suite rápida y un único test inestable conocido, una nota compartida y una corrección esta semana ganan a un sistema de seguimiento. La detección dedicada y la cuarentena compensan cuando la suite, el número de colaboradores o el número de pipelines hace imposible que alguien recuerde qué fallos son ruido.
- **Rutas críticas.** La cuarentena es la herramienta equivocada para un test que protege pagos, integridad de datos o seguridad. Esos tests deben bloquear hasta que se corrijan, aunque sea inconveniente.

## Detección de tests inestables con Tuist {#flaky-test-detection-with-tuist}

[Tuist](https://tuist.dev) registra cada intento de test desde Xcode, Gradle, Bazel, Elixir y otras integraciones compatibles, marca un test como inestable cuando falla y pasa sobre el mismo código, tanto entre reintentos como, para integraciones compatibles, entre ejecuciones de CI del mismo commit, y permite a los equipos silenciar u omitir tests inestables conocidos manualmente o mediante automatizaciones mientras se corrigen. El soporte y los requisitos varían según la toolchain:

- <.localized_link href="/guides/features/test-insights/flaky-tests">Tests inestables</.localized_link> explica cómo funcionan la detección, la cuarentena y las pruebas de estrés de nuevos tests, con una guía por toolchain.
- <.localized_link href="/guides/features/test-insights">Análisis de tests</.localized_link> cubre el registro de resultados de tests en primer lugar.
- [Mis tests son inestables](https://tuist.dev/solutions/flaky-tests) es una guía práctica para diagnosticar y contener tests inestables en equipo.

Referencia relacionada: <.localized_link href="/references/concepts/build-cache">¿Qué es una caché de compilación?</.localized_link>, incluido cómo interactúan los resultados de tests almacenados en caché con la inestabilidad.
