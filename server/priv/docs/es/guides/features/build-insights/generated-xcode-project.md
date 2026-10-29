---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Build insights · Features · Guides · Tuist",
  "description": "Track build analytics for a Tuist-generated Xcode project on the Tuist dashboard."
}
---
# Proyecto de Xcode generado {#generated-xcode-project-build-insights}

> [!NOTE]
> Los esquemas generados automáticamente incluyen la post-acción `tuist inspect build`.

>
> Si no deseas rastrear insights de compilación en esquemas generados, desactívalo usando [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

Si estás usando proyectos generados con esquemas personalizados, necesitas añadir la post-acción tú mismo. Para [Mise](https://mise.jdx.dev/):

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

Si no estás usando Mise, debes asegurarte de que `tuist` esté disponible en el entorno del esquema, ya que las post-acciones de Xcode no heredan el `PATH` de tu shell. Para instalaciones de [Homebrew](https://brew.sh/):

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

## Insights de compilación en CI {#continuous-integration}

Para rastrear insights de compilación en CI, asegúrate de que la CI esté <.localized_link href="/guides/integrations/continuous-integration#authentication">autenticada</.localized_link>.

Para CI impulsada por Xcodebuild necesitas:
- Usa <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> al invocar acciones de `xcodebuild`.
- Añade `-resultBundlePath` a tu comando de `xcodebuild`.

Sin `-resultBundlePath`, no se generan los registros de actividad ni los paquetes de resultados requeridos, y `tuist inspect build` no puede analizar la compilación.

## Métricas de la máquina {#machine-metrics}

Los insights de compilación pueden incluir métricas de rendimiento a nivel de máquina (CPU, memoria, red y uso de disco) capturadas durante la compilación. Para habilitar esto, configura un daemon ligero en segundo plano que muestree continuamente las métricas del sistema:

```bash
tuist setup insights
```

Esto ejecuta un daemon local que muestrea métricas en segundo plano. Los datos son recogidos automáticamente por `tuist inspect build` y subidos junto con el informe de compilación.

> [!TIP]
> **Ci**
>
> Ejecuta `tuist setup insights` en tus máquinas de CI antes de compilar para capturar también las métricas de la máquina allí.

Para dejar de recopilar métricas de la máquina, ejecuta:

```bash
tuist teardown insights
```

Esto descarga el LaunchAgent del daemon, elimina su plist y borra las métricas muestreadas y los registros del daemon de `~/.local/state`, por lo que no queda nada ejecutándose en segundo plano.


## Metadatos personalizados {#custom-metadata}

Puedes adjuntar metadatos a las compilaciones con variables de entorno para mejorar el filtrado.

### Variables de entorno

| Variable | Formato | Descripción |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Separado por comas | Múltiples etiquetas en una variable. |
| `TUIST_BUILD_VALUE_*` | Valor único | Par clave-valor donde el sufijo es la clave. |

### Ejemplos

Establece estos valores en la CI o en tu shell antes de invocar tu compilación:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
