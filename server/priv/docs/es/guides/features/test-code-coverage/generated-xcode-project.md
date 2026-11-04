---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Cobertura de código · Funcionalidades · Guías · Tuist",
  "description": "Mide la cobertura de código de un proyecto de Xcode generado por Tuist por archivo y por commit, incluyendo el código que omiten la caché binaria y los tests selectivos."
}
---
# Proyecto de Xcode generado {#generated-xcode-project-code-coverage}

> [!NOTE] EARLY ACCESS
> La cobertura de código para proyectos de Xcode está en acceso anticipado. [Ponte en contacto](mailto:contact@tuist.dev) para activarla en tu cuenta. Hasta entonces, Tuist no almacena la cobertura que suben tus ejecuciones.

La cobertura de código te indica qué líneas de tu código ejecutaron tus tests. Tuist sube la cobertura por línea de cada ejecución de `tuist test` y consolida las ejecuciones de un commit en una única cifra, para el proyecto, cada target y cada archivo. La página **Cobertura de código** del panel la muestra por commit y como tendencia para cada rama.

La cifra se mantiene precisa cuando Tuist omite trabajo. Los targets procedentes de la <.localized_link href="/guides/features/cache/module-cache">caché binaria</.localized_link> se compilan con contadores de cobertura, de modo que su código se mide igual que el compilado desde el origen. Y cuando los <.localized_link href="/guides/features/selective-testing/generated-xcode-project">tests selectivos</.localized_link> omiten un target de test, ese target conserva la cobertura que tenía en una ejecución anterior, gracias a la [cobertura a nivel de target](#target-level-coverage) que Tuist registra en cada ejecución.

## Configuración {#setup}

### Activar la cobertura {#turn-coverage-on}

Activa la cobertura en las opciones de generación de tu `Tuist.swift` y habilita la subida de cobertura, que está desactivada por defecto:

```swift
import ProjectDescription

let tuist = Tuist(
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

Con la opción de generación activada:

- La acción de test de cada esquema que genera Tuist recopila cobertura, al igual que la acción de test de cada esquema que definas y deje `coverage` sin establecer. Un esquema con `.options(coverage: false)` o `.options(coverage: true)` mantiene su valor. Los planes de test deciden la cobertura por sí mismos: para los planes de test que genera Tuist, pasa `coverage: true` a `.testPlans(_:coverage:)`.
- Los targets propios de tu proyecto se leen y se precargan en la caché binaria con contadores de cobertura en las configuraciones de Debug. Consulta [Cómo funciona](#instrumented-binaries).

Las variables de entorno `TUIST_COVERAGE_ENABLED` y `TUIST_COVERAGE_UPLOAD` (`1` o `0`) tienen prioridad sobre `enabled` y `upload`. Configúralas para todo un entorno, como un flujo de CI, en lugar de para un único comando, de modo que los comandos que precargan la caché y los que la leen coincidan.

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> La opción de generación cambia las claves de caché de los targets de tu proyecto y los hashes de tests selectivos de sus targets de test. Usa el mismo valor en todas las máquinas que compartan la caché y no lo derives del entorno (por ejemplo, de `Environment.isCI`). Una ejecución con la cobertura desactivada no reutiliza los binarios ni los resultados de tests selectivos de las ejecuciones con la cobertura activada.

### Excluir esquemas {#leave-schemes-out}

Algunas suites de test no deben formar parte de tu cobertura. Los tests de aceptación o end-to-end que controlan tu app o CLI desde otro proceso, por ejemplo, ejecutan código que la cobertura no puede ver, y recopilarla solo los ralentiza. Desactiva la cobertura en la acción de test de su esquema:

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

El esquema mantiene la cobertura desactivada independientemente de lo que indiquen la opción `Tuist.swift` o `TUIST_COVERAGE_ENABLED`, y sus ejecuciones no cuentan para la cobertura del commit. La cobertura se recopila por esquema, así que para excluir un target de test, muévelo a un esquema propio.

### Ejecutar tus tests {#run-your-tests}

Ejecuta tus tests con `tuist test`, como de costumbre:

```sh
tuist test
```

Tuist sube la cobertura que recopiló la ejecución junto con sus resultados de test. Esto incluye <.localized_link href="/guides/features/test-sharding/generated-xcode-project">ejecuciones fragmentadas</.localized_link> y ejecuciones que prueban productos compilados en otro job con `--without-building`. Para evitar que la cobertura de una ejecución llegue a Tuist, por ejemplo en jobs que ejecutan pull requests desde forks, establece `TUIST_COVERAGE_UPLOAD=0`.

### Completar cada commit en CI {#complete-each-commit}

La cobertura de un commit suele provenir de varios jobs: uno por esquema, por fragmento o por plataforma. Tuist no puede saber cuándo ha informado el último de ellos, así que debes indicárselo. Cuando hayan terminado todos los jobs de test de un commit, ejecuta esto en un job que dependa de todos ellos:

```sh
tuist coverage complete
```

El comando lee el commit desde el checkout o desde tu proveedor de CI; pasa `--commit <sha>` para indicar otro. Hasta que un commit esté completo, su cobertura aparece como **En progreso** y queda fuera de la tendencia de su rama.

### Ejecutar toda la suite en tu rama principal {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> Los tests selectivos solo mantienen completa la cobertura de un commit si hay una ejecución anterior de la que arrastrar los targets omitidos. Programa una ejecución de todos los tests, sin tests selectivos, en tu rama principal:
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> Una vez en cada merge es lo ideal. Diaria o semanalmente puede ser suficiente para un repositorio con pocos cambios. La cobertura registrada caduca a los 90 días, así que ejecútala con más frecuencia que eso.

La cobertura arrastrada depende de ejecuciones completas. Estas actualizan la cobertura registrada de cada target antes de que caduque y proporcionan a Tuist un estado reciente de los archivos que una ejecución selectiva no compila. Cuanto más cambie un repositorio entre ejecuciones completas, con más frecuencia una ejecución selectiva encontrará un archivo que haya cambiado desde entonces y la cobertura de su commit será **Incompleta**.

## Cobertura a nivel de target {#target-level-coverage}

La cobertura de una ejecución indica qué ejecutó toda la ejecución, no qué ejecutó cada target de test. Cuando los tests selectivos omiten un target, Tuist necesita saber qué ejecutó ese target en una ejecución anterior para arrastrar su cobertura.

Por eso, en cada ejecución, Tuist también registra qué archivos y líneas ejecutó cada target de test. Los lee de la cobertura que Xcode escribe para cada proceso de test, así que no hay nada que enlazar ni configurar. Se registra en macOS y en el simulador de iOS, no en dispositivos. Los tests de UI no registran nada sobre la app que controlan, porque el código de la app se ejecuta en un proceso propio.

## Cómo funciona {#how-it-works}

### Binarios instrumentados {#instrumented-binaries}

Un target de la caché binaria es un binario precompilado, y una ejecución de test solo puede medir su código si el binario se compiló con contadores de cobertura. Con la cobertura activada, la caché binaria conserva una variante instrumentada de los targets propios de tu proyecto, y cada comando lee y precarga esa variante:

- Las **configuraciones de Debug** usan la variante instrumentada: `tuist cache` la precarga, y `tuist generate` y `tuist test` la leen.
- Las **configuraciones de Release** siempre usan la variante normal, por lo que lo que publiques nunca lleva contadores de cobertura.
- Los **paquetes externos** siempre usan la variante normal. Tuist solo mide el código de tu repositorio.

Precarga la caché con la cobertura activada, en el mismo entorno que tus jobs de test, para que `tuist test` encuentre binarios instrumentados. Cuando una ejecución recopila cobertura pero obtiene tus targets de la caché como binarios normales, Tuist te avisa y su código no se mide. La <.localized_link href="/guides/features/cache/module-cache#code-coverage">caché de módulos</.localized_link> documenta las variantes en detalle.

### Rutas entre máquinas {#paths-across-machines}

Los binarios instrumentados registran sus rutas de origen relativas al checkout en el que se compilaron, de modo que un binario precargado en CI mide los archivos correctos en la máquina de cualquier desarrollador.

La <.localized_link href="/guides/features/cache/xcode-cache">caché de Xcode</.localized_link> funciona de la misma manera mediante el mapeo de prefijos, que Tuist desactiva por defecto en las compilaciones que recopilan cobertura, porque el informe de cobertura propio de Xcode no puede resolver rutas mapeadas. En Xcode 27 y versiones posteriores, con `enableCaching` activado, `prefixMapping: true` lo mantiene activado, de modo que las compilaciones de cobertura también comparten resultados de compilación entre checkouts:

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

La subida de Tuist resuelve las rutas mapeadas, pero el informe de cobertura de Xcode y `xccov` pueden excluir esos archivos. Consulta <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Cobertura con mapeo de prefijos</.localized_link>.

### Tests omitidos {#skipped-tests}

Los tests selectivos omiten un target de test cuando una ejecución anterior exitosa ya lo probó con el mismo hash. El hash abarca las fuentes del target, sus tests y todas sus dependencias, por lo que el mismo hash significa los mismos tests sobre el mismo código. Tuist reutiliza la [cobertura a nivel de target](#target-level-coverage) que esa ejecución anterior registró para el target. Si no registró ninguna, por ejemplo porque la cobertura estaba desactivada entonces o la ejecución tiene más de 90 días, no hay nada que arrastrar y el commit está **Incompleto**.

Una ejecución selectiva tampoco compila todos los archivos. Para los archivos que no compiló, Tuist toma las líneas de la ejecución completa anterior más cercana, siempre que los archivos no hayan cambiado desde entonces. Por eso importan las [ejecuciones completas](#full-runs) en tu rama por defecto.

Los tests que omites tú mismo, con `--skip-test-targets` o `-skip-testing`, no se arrastran: un commit cuyas ejecuciones los dejaron fuera está **Incompleto**, a menos que otra ejecución en el commit los haya ejecutado. Los tests que la cuarentena omite no forman parte de la cobertura en absoluto: Tuist ni los arrastra ni marca el commit como **Incompleto** por ellos.

### Commits completos e incompletos {#commit-status}

Cada commit en el dashboard tiene un estado:

| Estado | Significado |
| --- | --- |
| En progreso | Las ejecuciones han reportado cobertura, pero `tuist coverage complete` aún no se ha ejecutado para el commit. |
| Completo | Todos los tests de los esquemas del commit se ejecutaron o fueron arrastrados. |
| Incompleto | No se pudo determinar parte de la cobertura, por lo que la cifra es un límite inferior. |
| No medido | Ninguna ejecución reportó cobertura para el commit. |

La tendencia de una rama solo incluye commits completos. Un commit es incompleto cuando, por ejemplo:

- Los tests selectivos omitieron un target que no pudo ser arrastrado: la ejecución anterior no registró cobertura para él, un archivo que la ejecución selectiva no compiló cambió desde la última ejecución completa, o el commit cambió archivos que afectan a todos los targets, como `Package.resolved`, `Project.swift` o un `.xcconfig`.
- Una ejecución omitió tests con `--skip-test-targets` o `-skip-testing`, y ninguna otra ejecución en el commit los ejecutó.
- Una ejecución obtuvo tus targets de la caché binaria como binarios normales.
- Todas las ejecuciones de un esquema se restringieron con `-only-testing`.
- La cobertura de un esquema provino únicamente de ejecuciones de CI en un checkout con cambios sin confirmar.

## Impacto en el rendimiento {#performance-impact}

Recopilar cobertura añade sobrecarga, principalmente después de que terminan los tests, mientras Xcode escribe su informe de cobertura y Tuist exporta la cobertura. Compilar y ejecutar los tests lleva aproximadamente el mismo tiempo que sin ella. Las compilaciones instrumentadas también ocupan más espacio en disco, en DerivedData y en la caché binaria de Debug. Las compilaciones de Release y los archives no se ven afectados.

## Limitaciones {#limitations}

### Compilaciones de Release de esquemas que recopilan cobertura {#release-builds}

Cuando la acción de test de un esquema recopila cobertura, Xcode también instrumenta los targets que `xcodebuild build` compila desde fuente para ese esquema, en cualquier configuración, incluida Release. `xcodebuild archive` ignora la configuración, por lo que los archives nunca se instrumentan. Distribuye archives, o compila productos de Release desde un esquema con `.options(coverage: false)`.

### Otras herramientas de cobertura {#other-coverage-tools}

`-enableCodeCoverage YES` solo decide si una ejecución recopila cobertura, como en Xcode. No hace que Tuist lea binarios instrumentados de la caché, así que usa la opción `Tuist.swift` o `TUIST_COVERAGE_ENABLED` en su lugar.

Para alimentar otra herramienta de cobertura, haz que `tuist test` escriba la cobertura de cada ejecución como LCOV. Es la misma cobertura que Tuist sube, con rutas relativas al repositorio e incluyendo el código de la caché binaria:

```sh
tuist test --coverage-output-path coverage
```

Cada ejecución escribe `coverage/<result bundle name>.lcov`. Fusiona los archivos de una ejecución fragmentada con `lcov -a`. La opción necesita la subida de cobertura activada.

El informe de cobertura propio de Xcode, y las herramientas que lo leen, solo incluyen targets que Xcode compiló en esa ejecución, nunca código que provino de la caché binaria. La subida de Tuist mide ambos. Si quieres la cobertura de un target en el informe de Xcode, genera el proyecto con ese target compilado desde fuente: `tuist generate MyTarget` mantiene `MyTarget` como fuente y toma el resto de la caché.

## Consultar cobertura {#querying}

Los comandos `tuist coverage` leen lo que muestra el dashboard. Sin `--commit`, leen el último commit completo de `--branch`, o de tu rama por defecto:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

Todos aceptan `--json` para scripting. Los mismos datos están disponibles para agentes a través del <.localized_link href="/guides/features/agentic-coding/mcp">servidor Model Context Protocol</.localized_link>.
