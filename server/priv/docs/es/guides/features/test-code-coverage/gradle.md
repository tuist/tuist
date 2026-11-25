---
{
  "title": "Cobertura de código con Gradle",
  "titleTemplate": ":title · Cobertura de código · Funcionalidades · Guías · Tuist",
  "description": "Sube la cobertura de código de los tests de tu proyecto Gradle, medida con JaCoCo, y haz un seguimiento por archivo, por proyecto y por commit."
}
---
# Cobertura de código con Gradle {#gradle-code-coverage}

La cobertura de código te indica qué líneas de tu código ejecutaron tus tests. El plugin de Gradle de Tuist mide la cobertura de tus tareas de test con JaCoCo y la sube en cada ejecución de tests, y Tuist consolida las ejecuciones de un commit en una única cifra, para el proyecto, cada proyecto de Gradle y cada archivo. La página **Cobertura de código** del panel la muestra por commit y como tendencia para cada rama.

> [!IMPORTANT]
> **Requisitos**
>
> - El plugin de Gradle `dev.tuist` aplicado, como se describe en <.localized_link href="/guides/get-started/gradle-project">Comenzar con un proyecto de Gradle</.localized_link>
> - Tu proyecto en un repositorio Git: una ejecución fuera de él sube sus resultados de tests pero no la cobertura

## Configuración {#setup}

### Activar la cobertura {#turn-coverage-on}

Activa la cobertura en el bloque `tuist` de tu `settings.gradle.kts`:

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

O actívala para una invocación concreta, como un trabajo de CI, con una variable de entorno, que tiene prioridad sobre la configuración en cualquier caso:

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

Las tareas de test con la cobertura activada y desactivada tienen entradas separadas en la caché de compilación (consulta [Impacto en el rendimiento](#performance-impact)), así que prefiere la configuración cuando tus compilaciones de CI y locales compartan una caché de compilación: activar la cobertura solo en CI evita que reutilicen los resultados de tests entre sí.

Con la cobertura activada, el plugin aplica el plugin `jacoco` de Gradle a cada proyecto JVM. El agente de JaCoCo proviene de los repositorios de tu proyecto, como ocurriría si aplicaras el plugin tú mismo. Un proyecto que ya configure JaCoCo mantiene su configuración y sus propios informes siguen funcionando.

El plugin solo informa de la cobertura del código de tu repositorio, por lo que limita JaCoCo a él: a menos que una tarea de test establezca por sí misma `includes` de JaCoCo, el agente instrumenta solo los paquetes de las clases que compila tu repositorio. Las dependencias, el framework de Android y tus frameworks de test se ejecutan sin instrumentar, lo que mantiene pequeños los datos de JaCoCo y las entradas de la caché de compilación de las tareas de test.

### Proyectos de Android {#android-projects}

El plugin mide los tests unitarios locales de los proyectos de Android, como `testDebugUnitTest`. Los tests instrumentados que se ejecutan en un dispositivo o emulador no se miden.

Si tus tests unitarios usan Robolectric, indica a JaCoCo que incluya las clases que carga Robolectric. Robolectric define las clases de tu app en su propio class loader y JaCoCo omite esas clases por defecto, por lo que el código que ejecutan esos tests aparecería como no cubierto. En el `build.gradle.kts` del proyecto de Android:

```kotlin
pluginManager.withPlugin("jacoco") {
    tasks.withType<Test>().configureEach {
        extensions.configure<JacocoTaskExtension> {
            isIncludeNoLocationClasses = true
            excludes = listOf("jdk.internal.*")
        }
    }
}
```

El bloque solo se aplica cuando la cobertura está activada, porque es entonces cuando el plugin aplica `jacoco`.

Los tests unitarios de Android se ejecutan en JUnit 4 por defecto, lo que registra la cobertura pero no [qué código ejecutó cada test](#per-test-evidence). Para registrarlo, ejecútalos en la JUnit Platform a través de JUnit Vintage.

### Ejecuciones fragmentadas {#sharded-runs}

Cuando <.localized_link href="/guides/features/test-sharding/gradle">fragmentas tus tests</.localized_link>, cada fragmento que se ejecuta con la cobertura activada informa de la cobertura de los tests que ejecutó, y Tuist combina los fragmentos de una ejecución en una única cifra. Un fragmento ejecuta parte de la suite a propósito, por lo que no deja incompleta la cobertura del commit.

### Completar cada commit en CI {#complete-each-commit}

La cobertura de un commit suele provenir de varios trabajos, como uno por fragmento. Tuist no puede saber cuándo ha informado el último de ellos, así que debes indicárselo. Una vez que haya terminado cada trabajo de test de un commit, ejecuta esto en un trabajo que dependa de todos ellos:

```sh
./gradlew tuistCoverageComplete
```

Cuando un único trabajo ejecuta todos los tests de un commit, ejecuta la tarea como un paso después de los tests, incluso cuando los tests fallen: una ejecución con tests fallidos sigue informando de su cobertura.

La tarea lee el commit desde `HEAD` del checkout, el commit sobre el que se ejecutaron tus tests; pasa `-Ptuist.coverage.commit=<sha>` para indicar otro distinto. Hasta que un commit esté completo, su cobertura aparece como **En progreso** y queda fuera de la tendencia de su rama.

## Cómo funciona {#how-it-works}

### Qué mide Tuist {#what-tuist-measures}

- **Proyectos.** Cada proyecto de Gradle es un módulo en el panel, con su propia cobertura.
- **Solo código de producto.** Las clases compiladas a partir de conjuntos de fuentes de test son código de test. Tuist las almacena pero las excluye de todas las cifras.
- **Archivos de tu repositorio.** Una clase cuenta para el archivo fuente del que se compiló, bajo su ruta en tu repositorio. Las fuentes generadas y los archivos que Git ignora no se informan.
- **Si se ejecutó cada línea.** JaCoCo registra si el código se ejecutó, no cuántas veces, por lo que los recuentos de ejecución del panel son 0 o 1.

### Qué código ejecutó cada test {#per-test-evidence}

Para los tests que se ejecutan en la JUnit Platform (JUnit 5, o JUnit 4 a través de JUnit Vintage), el plugin también registra qué código ejecutó cada test y qué ejecutó cada clase de test fuera de sus tests, como en `@BeforeAll`. Esto es lo que permite a Tuist mantener la cobertura de los tests que una ejecución omite (consulta [Tests omitidos](#skipped-tests)). No hace falta añadir nada a tus tests.

Esto funciona cuando cada JVM de test ejecuta un test a la vez, que es cómo Gradle ejecuta los tests a menos que actives la ejecución paralela de JUnit. Ejecutar clases de test en varias JVM con `maxParallelForks` es correcto. Los tests que se ejecutan al mismo tiempo en una JVM siguen contando en la cobertura, pero no uno por uno.

### La caché de compilación {#build-cache}

Una tarea de test que Gradle restaura desde la caché de compilación, o que está actualizada, no ejecuta tests. Su cobertura sigue subiéndose: los datos de JaCoCo son una de las salidas de la tarea, registrados por la ejecución que ejecutó sus tests con las mismas entradas.

### Tests omitidos {#skipped-tests}

Cuando una ejecución omite tests, Tuist completa lo que cubrieron a partir de una ejecución anterior, siempre que el código que ejecutaron no haya cambiado. Cuando no puede, la cobertura del commit es **Incompleta**. Lo que una ejecución omite:

- **Se excluye la tarea de test de un proyecto** con `-x :app:test`. Sus tests se mantienen a partir de la última ejecución de ellos cuyo código no haya cambiado.
- **Tests de algunos proyectos** con `./gradlew :core:test`, o **algunos tests** con `--tests`. La ejecución cubre solo lo que solicitaste, por lo que el commit es incompleto a menos que otra ejecución del commit ejecutara todo.
- **Una tarea de test que se detuvo en su primer fallo** (`failFast`).

Algunos tests se omiten a propósito y no dejan incompleto un commit:

- **Filtros en tu script de compilación**, como `filter { excludeTestsMatching(...) }`, que definen qué ejecuta tu suite.
- **Tareas de test que tu script de compilación desactiva**, con `enabled = false` o un `onlyIf` que las omite.
- **Tests que <.localized_link href="/guides/features/test-insights/flaky-tests/gradle">cuarentena</.localized_link> omite.** Se excluyen como si se hubieran eliminado, por lo que las líneas que solo ellos cubrieron cuentan como no cubiertas.
- **Los tests de otros fragmentos**, cuando [fragmentas tus tests](#sharded-runs).

### Commits completos e incompletos {#commit-status}

| Estado | Significado |
| --- | --- |
| En progreso | Las ejecuciones han reportado cobertura, pero `tuistCoverageComplete` aún no se ha ejecutado para el commit. |
| Completo | Cada test de las ejecuciones del commit se ejecutó, se mantuvo o se omitió a propósito. |
| Incompleto | No se pudo determinar parte de la cobertura, por lo que la cifra es un límite inferior. |
| No medido | Ninguna ejecución reportó cobertura para el commit. |

La tendencia de una rama solo incluye commits completos.

## Impacto en el rendimiento {#performance-impact}

JaCoCo instrumenta las clases mientras la JVM de test las carga, por lo que tus clases compiladas y las entradas de la caché de compilación de las tareas de compilación permanecen iguales con la cobertura activada o desactivada. Las tareas que leen cada configuración de dependencias, como los generadores de SBOM, también ven el agente de JaCoCo, por lo que sus salidas cambian cuando activas la cobertura. Los tests se ejecutan un poco más despacio y el plugin lee los datos de JaCoCo una vez que finalizan las tareas de test. Las tareas de test con la cobertura activada y desactivada tienen entradas de caché de compilación separadas, por lo que la primera ejecución con la cobertura activada ejecuta los tests incluso cuando sus resultados sin cobertura están en caché.

## Limitaciones {#limitations}

- **Proyectos aislados y configuración bajo demanda.** Estas compilaciones no configuran todos los proyectos, por lo que el plugin no puede saber qué tests de proyectos omitió una ejecución, y una ejecución de tests de algunos proyectos cuenta como completa.
- **Sin cobertura desde pull requests de forks.** La cobertura solo se sube mediante ejecuciones que se autentican con Tuist, y la CI suele retener secretos y tokens de identidad de las pull requests abiertas desde forks.

## Consulta de cobertura {#querying}

La página **Cobertura de código** del panel muestra la cifra de cada commit, sus módulos y sus archivos, con las líneas que cubrió cada ejecución. Los mismos datos están disponibles para los agentes a través del <.localized_link href="/guides/features/agentic-coding/mcp">servidor de Model Context Protocol</.localized_link>.
