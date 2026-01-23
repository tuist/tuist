---
{
  "title": "Test Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your tests to identify slow and flaky tests."
}
---
# Información sobre la prueba {#test-insights}

::: advertencia REQUISITOS
<!-- -->
- Una cuenta y un proyecto
  <LocalizedLink href="/guides/server/accounts-and-projects">Tuist.</LocalizedLink>
<!-- -->
:::

Test Insights te ayuda a supervisar el estado de tu conjunto de pruebas
identificando las pruebas lentas o comprendiendo rápidamente las ejecuciones de
CI fallidas. A medida que tu conjunto de pruebas crece, se hace cada vez más
difícil detectar tendencias como pruebas que se ralentizan gradualmente o fallos
intermitentes. Tuist Test Insights te proporciona la visibilidad que necesitas
para mantener un conjunto de pruebas rápido y fiable.

Con Test Insights, puede responder a preguntas como:
- ¿Mis pruebas se han vuelto más lentas? ¿Cuáles?
- ¿Qué pruebas son inestables y requieren atención?
- ¿Por qué ha fallado mi ejecución de CI?

## Configuración {#setup}

Para empezar a realizar el seguimiento de sus pruebas, puede aprovechar el
comando `tuist inspect test` añadiéndolo a la post-acción de prueba de su
esquema:

![Acción posterior para inspeccionar
pruebas](/images/guides/features/insights/inspect-test-scheme-post-action.png)

Si utiliza [Mise](https://mise.jdx.dev/), su script deberá activar `tuist` en el
entorno post-action:
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
configuración de compilación de un objetivo de su proyecto, de forma que pueda
ejecutar Mise desde el directorio apuntado por $SRCROOT.
<!-- -->
:::

Ahora se realiza un seguimiento de tus pruebas siempre que estés conectado a tu
cuenta de Tuist. Puedes acceder a la información de tus pruebas en el panel de
control de Tuist y ver cómo evolucionan con el tiempo:

![Panel de control con información de la
prueba](/images/guides/features/insights/tests-dashboard.png)

Además de las tendencias generales, también puedes profundizar en cada prueba
individual, por ejemplo, al depurar fallos o pruebas lentas en la CI:

![Detalle de la prueba](/images/guides/features/insights/test-detail.png)

## Proyectos generados {#generated-projects}

::: info
<!-- -->
Los esquemas generados automáticamente incluyen automáticamente la prueba de
inspección del asistente `y la acción posterior`.
<!-- -->
:::
> 
> Si no te interesa realizar un seguimiento de la información de las pruebas en
> tus esquemas generados automáticamente, desactívalos utilizando la opción de
> generación
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>.

Si utiliza proyectos generados con esquemas personalizados, puede configurar
acciones posteriores para obtener información sobre las pruebas:

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
            buildAction: .buildAction(targets: ["MyApp"]),
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

Si no utilizas Mise, tus scripts se pueden simplificar a:

```swift
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

Para realizar un seguimiento de la información de las pruebas en CI, deberá
asegurarse de que su CI esté
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticado</LocalizedLink>.

Además, tendrás que:
- Utilice el comando
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> al invocar acciones `xcodebuild`.
- Añade `-resultBundlePath` a tu invocación `xcodebuild`.

Cuando `xcodebuild` prueba tu proyecto sin `-resultBundlePath`, no se generan
los archivos de paquetes de resultados necesarios. La acción posterior `tuist
inspect test` requiere estos archivos para analizar tus pruebas.
