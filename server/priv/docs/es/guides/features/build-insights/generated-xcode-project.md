---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Análisis de compilaciones · Funcionalidades · Guías · Tuist",
  "description": "Haz seguimiento de las analíticas de compilación para un proyecto de Xcode generado con Tuist en el panel de control de Tuist."
}
---
# Proyecto de Xcode generado {#generated-xcode-project-build-insights}

> [!NOTE]
> Los esquemas generados automáticamente incluyen la acción posterior `tuist inspect build`.

>
> Si no quieres hacer seguimiento del análisis de compilaciones en esquemas generados, desactívalo con [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

Si usas proyectos generados con esquemas personalizados, debes añadir la acción posterior tú mismo. Para [Mise](https://mise.jdx.dev/):

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

Si no usas Mise, debes asegurarte de que `tuist` esté disponible en el entorno del esquema, ya que las acciones posteriores de Xcode no heredan el `PATH` de tu shell. Para instalaciones de [Homebrew](https://brew.sh/):

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

## Análisis de compilaciones en CI {#continuous-integration}

Para hacer seguimiento del análisis de compilaciones en CI, asegúrate de que CI esté <.localized_link href="/guides/integrations/continuous-integration#authentication">autenticado</.localized_link>.

Para CI basado en Xcodebuild debes:
- Usa <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> al invocar acciones de `xcodebuild`.
- Añade `-resultBundlePath` a tu comando de `xcodebuild`.

Sin `-resultBundlePath`, no se generan los registros de actividad ni los paquetes de resultados necesarios y `tuist inspect build` no puede analizar la compilación.

## Métricas de la máquina {#machine-metrics}

El análisis de compilaciones puede incluir métricas de rendimiento a nivel de máquina (CPU, memoria, red y uso de disco) capturadas durante la compilación. Para habilitarlo, configura un demonio ligero en segundo plano que tome muestras continuas de las métricas del sistema:

```bash
tuist setup insights
```

Esto ejecuta un demonio local que toma muestras de métricas en segundo plano. Los datos son recogidos automáticamente por `tuist inspect build` y se suben junto con el informe de compilación.

> [!TIP]
> **Ci**
>
> Ejecuta `tuist setup insights` en tus máquinas de CI antes de compilar para capturar también las métricas de la máquina allí.

Para dejar de recopilar métricas de la máquina, ejecuta:

```bash
tuist teardown insights
```

Esto descarga el LaunchAgent del demonio, elimina su plist y borra las métricas muestreadas y los registros del demonio de `~/.local/state`, de modo que no quede nada ejecutándose en segundo plano.


## Metadatos personalizados {#custom-metadata}

Puedes adjuntar metadatos a las compilaciones mediante variables de entorno para mejorar el filtrado.

### Variables de entorno

| Variable | Formato | Descripción |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Separado por comas | Varias etiquetas en una sola variable. |
| `TUIST_BUILD_VALUE_*` | Valor único | Par clave-valor donde el sufijo es la clave. |

### Ejemplos

Establece estos valores en CI o en tu shell antes de invocar tu compilación:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
