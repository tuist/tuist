---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Análisis de compilaciones · Funcionalidades · Guías · Tuist",
  "description": "Sigue las analíticas de compilación de un proyecto de Xcode generado por Tuist en el panel de control de Tuist."
}
---
# Proyecto de Xcode generado {#generated-xcode-project-build-insights}

> [!NOTE]
> Los esquemas generados automáticamente incluyen la acción posterior `tuist inspect build`.
>
> Si no quieres realizar el seguimiento de los análisis de compilaciones en los esquemas generados, desactívalo mediante [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

Si utilizas proyectos generados con esquemas personalizados, debes añadir la acción posterior tú mismo. Para [Mise](https://mise.jdx.dev/):

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
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Si no utilizas Mise, debes asegurarte de que `tuist` esté disponible en el entorno del esquema, ya que las acciones posteriores de Xcode no heredan el `PATH` de tu shell. Para instalaciones de [Homebrew](https://brew.sh/):

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: """
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            tuist inspect build
            """,
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
