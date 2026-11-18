---
{
  "title": "Análisis de tests en Xcode",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Haz seguimiento de las métricas de tests en Xcode para identificar tests lentos e inestables con el análisis de tests de Tuist."
}
---
# Análisis de tests de Xcode {#xcode-test-insights}

Tuist Test Insights te ofrece análisis de tests de Xcode para monitorizar la salud de tu suite de tests identificando tests lentos o comprendiendo rápidamente ejecuciones de CI fallidas. A medida que tu suite de tests crece, resulta cada vez más difícil detectar tendencias como tests que se ralentizan gradualmente o fallos intermitentes. Tuist Test Insights te proporciona la visibilidad necesaria para mantener una suite de tests rápida y fiable.

Con Test Insights, puedes responder a preguntas como:
- ¿Se han vuelto más lentos mis tests? ¿Cuáles?
- ¿Qué tests son inestables y necesitan atención?
- ¿Por qué ha fallado mi ejecución de CI?

## Configuración {#setup}

Para empezar a trackear tus tests, puedes aprovechar el comando `tuist inspect test` añadiéndolo a la post-acción de test de tu scheme:

![Post-acción para inspeccionar tests](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

Si estás usando [Mise](https://mise.jdx.dev/), tu script deberá activar `tuist` en el entorno de la post-acción:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise y rutas del proyecto**
>
> La variable de entorno `PATH` de tu entorno no se hereda en la post-acción del scheme, por lo que debes usar la ruta absoluta de Mise, que dependerá de cómo hayas instalado Mise. Además, no olvides heredar la configuración de compilación de un target de tu proyecto para poder ejecutar Mise desde el directorio indicado por $SRCROOT.

Tus ejecuciones de tests se trackean siempre que hayas iniciado sesión en tu cuenta de Tuist. Puedes acceder a tus análisis de tests en el dashboard de Tuist y ver cómo evolucionan con el tiempo:

![Dashboard con análisis de tests](/images/guides/features/build-insights/tests-dashboard.png)

Además de las tendencias generales, también puedes profundizar en cada test individual, por ejemplo al depurar fallos o tests lentos en la CI:

![Detalle del test](/images/guides/features/build-insights/test-detail.png)

## Proyectos generados {#generated-projects}

> [!NOTE]
> Los schemes autogenerados incluyen automáticamente la post-acción `tuist inspect test`.
>
> Si no te interesa trackear los análisis de tests en tus schemes autogenerados, desactívalos mediante la opción de generación [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

Si usas proyectos generados con schemes personalizados, puedes configurar post-acciones para los análisis de tests:

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

Si no usas Mise, tus scripts pueden simplificarse a:

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

## Integración continua {#continuous-integration}

Para trackear los análisis de tests en la CI, deberás asegurarte de que tu CI esté <.localized_link href="/guides/server/authentication#continuous-integration">autenticada</.localized_link>.

Además, necesitarás either:
- Usar el comando <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> al invocar acciones de `xcodebuild`.
- Añadir `-resultBundlePath` a tu invocación de `xcodebuild`.

Cuando `xcodebuild` prueba tu proyecto sin `-resultBundlePath`, no se generan los archivos de result bundle necesarios. La post-acción `tuist inspect test` requiere estos archivos para analizar tus tests.

### Historial de Git {#git-history}

En la CI, Tuist también sube el historial de commits del checkout: SHAs de los commits, sus padres, fechas de commit y la rama en la que estaba la ejecución y la rama base de su pull request. No se suben contenidos de archivos, mensajes de commit ni autores. Esto es lo que indica a Tuist qué commits llegaron a tu rama por defecto, por ejemplo los que probó una cola de merge. Tuist lee el historial que ya tiene el checkout y, cuando el checkout no tiene la rama base, solicita al remoto su último commit (`git ls-remote`). Fuera de la cobertura de código, no obtiene historial. Con cobertura de código, se amplía un checkout superficial, sin contenidos de archivo, para encontrar dónde se bifurcó una pull request y alcanzar los commits que Tuist ya tiene, de modo que nunca se sube un commit sin el padre sobre el que se asienta.

| Variable | Efecto |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | No lee ni sube ningún historial de Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Lee solo el checkout, sin contactar con el remoto. |
