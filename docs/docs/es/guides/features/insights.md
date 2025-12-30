---
{
  "title": "Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your projects to maintain a product developer environment."
}
---
# Perspectivas {#insights}

::: advertencia REQUISITOS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Cuenta tuista y proyecto</LocalizedLink>
<!-- -->
:::

Trabajar en grandes proyectos no debería ser una tarea pesada. De hecho, debería
ser tan agradable como trabajar en un proyecto que empezaste hace sólo dos
semanas. Una de las razones por las que no lo es es porque a medida que el
proyecto crece, la experiencia del desarrollador se resiente. Los tiempos de
compilación aumentan y las pruebas se vuelven lentas y poco fiables. A menudo es
fácil pasar por alto estos problemas hasta que llega un momento en que se
vuelven insoportables; sin embargo, en ese punto, es difícil abordarlos. Tuist
Insights le proporciona las herramientas para supervisar la salud de su proyecto
y mantener un entorno de desarrollo productivo a medida que su proyecto escala.

En otras palabras, Tuist Insights te ayuda a responder a preguntas como:
- ¿Ha aumentado significativamente el tiempo de construcción en la última
  semana?
- ¿Mis pruebas se han vuelto más lentas? ¿Cuáles?

::: info
<!-- -->
Tuist Insights está en fase inicial de desarrollo.
<!-- -->
:::

## Build {#build}

Si bien es probable que tenga algunas métricas para el rendimiento de los flujos
de trabajo de CI, es posible que no tenga la misma visibilidad en el entorno de
desarrollo local. Sin embargo, los tiempos de compilación locales son uno de los
factores más importantes que contribuyen a la experiencia del desarrollador.

Para empezar a realizar un seguimiento de los tiempos de compilación locales,
puede aprovechar el comando `tuist inspect build` añadiéndolo a la post-acción
de su esquema:

[Post-acción para inspeccionar
construcciones](/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info
<!-- -->
Recomendamos establecer "Proporcionar configuración de compilación desde" al
ejecutable o a tu objetivo de compilación principal para permitir que Tuist
rastree la configuración de compilación.
<!-- -->
:::

::: info
<!-- -->
Si no está utilizando <LocalizedLink href="/guides/features/projects">proyectos generados</LocalizedLink>, la acción post-scheme no se ejecuta en caso de que
falle la compilación.
<!-- -->
:::
> 
> Una característica no documentada de Xcode permite ejecutarlo incluso en este
> caso. Establezca el atributo `runPostActionsOnFailure` en `YES` en su esquema
> `BuildAction` en el archivo correspondiente `project.pbxproj` de la siguiente
> manera:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

En caso de que esté utilizando [Mise](https://mise.jdx.dev/), su script
necesitará activar `tuist` en el entorno post-acción:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: tip MISE & PROJECT PATHS
<!-- -->
La variable de entorno `PATH` de su entorno no es heredada por la acción
posterior al esquema, por lo que tendrá que utilizar la ruta absoluta de Mise,
que dependerá de cómo haya instalado Mise. Además, no olvide heredar la
configuración de compilación de un objetivo de su proyecto para poder ejecutar
Mise desde el directorio apuntado por $SRCROOT.
<!-- -->
:::


Ahora se hace un seguimiento de tus construcciones locales siempre que estés
conectado a tu cuenta de Tuist. Ahora puedes acceder a tus tiempos de
compilación en el panel de Tuist y ver cómo evolucionan con el tiempo:


::: consejo
<!-- -->
Para acceder rápidamente al panel de control, ejecute `tuist project show --web`
desde la CLI.
<!-- -->
:::

(/images/guides/features/insights/builds-dashboard.png)[Panel de control con
información de construcción]

## Pruebas {#tests}

Además de realizar un seguimiento de las compilaciones, también puede supervisar
las pruebas. La información sobre las pruebas le ayuda a identificar las pruebas
lentas o a comprender rápidamente las ejecuciones CI fallidas.

Para iniciar el seguimiento de sus pruebas, puede aprovechar el comando `tuist
inspect test` añadiéndolo a la post-acción de prueba de su esquema:

[Acción posterior a la inspección de las
pruebas](/images/guides/features/insights/inspect-test-scheme-post-action.png)

En caso de que esté utilizando [Mise](https://mise.jdx.dev/), su script
necesitará activar `tuist` en el entorno post-acción:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE & PROJECT PATHS
<!-- -->
La variable de entorno `PATH` de su entorno no es heredada por la acción
posterior al esquema, por lo que tendrá que utilizar la ruta absoluta de Mise,
que dependerá de cómo haya instalado Mise. Además, no olvide heredar la
configuración de compilación de un objetivo de su proyecto para poder ejecutar
Mise desde el directorio apuntado por $SRCROOT.
<!-- -->
:::

Ahora puedes hacer un seguimiento de tus pruebas siempre que estés conectado a
tu cuenta de Tuist. Puedes acceder a los resultados de tus pruebas en el panel
de Tuist y ver cómo evolucionan con el tiempo:

(/images/guides/features/insights/tests-dashboard.png)[Panel de control con
información de prueba](/images/guides/features/insights/tests-dashboard.png)

Aparte de las tendencias generales, también puede profundizar en cada prueba
individual, como cuando se depuran fallos o pruebas lentas en el CI:

[Detalle de la prueba](/images/guides/features/insights/test-detail.png)

## Proyectos generados {#generated-projects}

::: info
<!-- -->
Los esquemas autogenerados incluyen automáticamente las post-acciones `tuist
inspect build` y `tuist inspect test`.
<!-- -->
:::
> 
> Si no le interesa realizar un seguimiento de los insights en sus esquemas
> autogenerados, desactívelos mediante las opciones de generación
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> y
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>.

Si está utilizando proyectos generados con esquemas personalizados, puede
configurar post-acciones tanto para build como para test insights:

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    // Build insights: Track build times and performance
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                // Run build post-actions even if the build fails
                runPostActionsOnFailure: true
            ),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Si no utiliza Mise, sus guiones pueden simplificarse a:

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: "tuist inspect build",
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
),
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## Integración continua (CI) {#continuous-integration-ci}

Para realizar un seguimiento de la creación y las pruebas en CI, deberá
asegurarse de que su CI está
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticado</LocalizedLink>.

Además, tendrá que:
- Utilice el comando
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> cuando invoque las acciones `xcodebuild`.
- Añada `-resultBundlePath` a su invocación `xcodebuild`.

Cuando `xcodebuild` construye o prueba su proyecto sin `-resultBundlePath`, no
se generan los archivos necesarios de registro de actividad y de paquete de
resultados. Las post-acciones `tuist inspect build` y `tuist inspect test`
requieren estos archivos para analizar sus construcciones y pruebas.
