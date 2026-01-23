---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your builds to maintain a productive developer environment."
}
---
# Crear información detallada {#build-insights}

::: advertencia REQUISITOS
<!-- -->
- Una cuenta y un proyecto
  <LocalizedLink href="/guides/server/accounts-and-projects">Tuist.</LocalizedLink>
<!-- -->
:::

Trabajar en proyectos grandes no debería ser una tarea pesada. De hecho, debería
ser tan agradable como trabajar en un proyecto que hayas empezado hace solo dos
semanas. Una de las razones por las que no lo es es porque, a medida que el
proyecto crece, la experiencia del desarrollador se ve afectada. Los tiempos de
compilación aumentan y las pruebas se vuelven lentas e inestables. A menudo es
fácil pasar por alto estos problemas hasta que llegan a un punto en el que se
vuelven insoportables; sin embargo, en ese momento, es difícil solucionarlos.
Tuist Insights le proporciona las herramientas necesarias para supervisar el
estado de su proyecto y mantener un entorno de desarrollo productivo a medida
que su proyecto crece.

En otras palabras, Tuist Insights te ayuda a responder preguntas como:
- ¿Ha aumentado significativamente el tiempo de compilación en la última semana?
- ¿Mis compilaciones son más lentas en CI en comparación con el desarrollo
  local?

Aunque probablemente dispongas de algunas métricas sobre el rendimiento de los
flujos de trabajo de CI, es posible que no tengas la misma visibilidad del
entorno de desarrollo local. Sin embargo, los tiempos de compilación locales son
uno de los factores más importantes que contribuyen a la experiencia del
desarrollador.

Para empezar a realizar un seguimiento de los tiempos de compilación locales,
puede aprovechar el comando `tuist inspect build` añadiéndolo a la acción
posterior de su esquema:

![Acción posterior para inspeccionar
compilaciones](/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info
<!-- -->
Recomendamos configurar «Proporcionar ajustes de compilación desde» en el
ejecutable o en tu objetivo de compilación principal para permitir que Tuist
realice un seguimiento de la configuración de compilación.
<!-- -->
:::

::: info
<!-- -->
Si no utiliza <LocalizedLink href="/guides/features/projects">proyectos
generados</LocalizedLink>, la acción posterior al esquema no se ejecuta en caso
de que la compilación falle.
<!-- -->
:::
> 
> Una característica no documentada de Xcode permite ejecutarlo incluso en este
> caso. Establezca el atributo `runPostActionsOnFailure` en `YES` en su esquema
> `BuildAction` en el archivo `project.pbxproj` correspondiente de la siguiente
> manera:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

Si utiliza [Mise](https://mise.jdx.dev/), su script deberá activar `tuist` en el
entorno post-action:
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
configuración de compilación de un objetivo de su proyecto, de forma que pueda
ejecutar Mise desde el directorio apuntado por $SRCROOT.
<!-- -->
:::


Ahora se realiza un seguimiento de tus compilaciones locales siempre que estés
conectado a tu cuenta de Tuist. Ahora puedes acceder a tus tiempos de
compilación en el panel de control de Tuist y ver cómo evolucionan con el
tiempo:


::: consejo
<!-- -->
Para acceder rápidamente al panel de control, ejecute `tuist project show --web`
desde la CLI.
<!-- -->
:::

![Panel de control con información sobre la
compilación](/images/guides/features/insights/builds-dashboard.png)

## Proyectos generados {#generated-projects}

::: info
<!-- -->
Los esquemas generados automáticamente incluyen automáticamente la acción
posterior « `tuist inspect build» (comprobar compilación del asistente) «` ».
<!-- -->
:::
> 
> Si no te interesa realizar un seguimiento de la información en tus esquemas
> generados automáticamente, desactívalos mediante la opción de generación
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>.

Si utiliza proyectos generados con esquemas personalizados, puede configurar
acciones posteriores para obtener información sobre la compilación:

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
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Si no utilizas Mise, tus scripts se pueden simplificar a:

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
)
```

## Integración continua (CI) {#continuous-integration-ci}

Para realizar un seguimiento de la información de compilación en CI, deberá
asegurarse de que su CI esté
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticada</LocalizedLink>.

Además, tendrás que:
- Utilice el comando
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> al invocar acciones `xcodebuild`.
- Añade `-resultBundlePath` a tu invocación `xcodebuild`.

Cuando `xcodebuild` compila tu proyecto sin `-resultBundlePath`, no se generan
los archivos de registro de actividad y del paquete de resultados necesarios. La
acción posterior `tuist inspect build` requiere estos archivos para analizar tus
compilaciones.
