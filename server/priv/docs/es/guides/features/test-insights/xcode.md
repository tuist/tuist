---
{
  "title": "Análisis de tests de Xcode",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Sigue las analíticas de tests de Xcode para identificar tests lentos e inestables con el análisis de tests de Tuist."
}
---
# Análisis de tests de Xcode {#xcode-test-insights}

Tuist Test Insights te ofrece análisis de tests de Xcode para monitorizar la salud de tu suite de tests identificando tests lentos o entendiendo rápidamente ejecuciones de CI fallidas. A medida que tu suite de tests crece, resulta cada vez más difícil detectar tendencias como tests que se ralentizan gradualmente o fallos intermitentes. Tuist Test Insights te proporciona la visibilidad necesaria para mantener una suite de tests rápida y fiable.

Con Test Insights, puedes responder a preguntas como:
- ¿Se han vuelto más lentos mis tests? ¿Cuáles?
- ¿Qué tests son inestables y necesitan atención?
- ¿Por qué ha fallado mi ejecución de CI?

## Configuración {#setup}

Para empezar a hacer seguimiento de tus tests, puedes aprovechar el comando `tuist inspect test` añadiéndolo a la post-acción de test de tu esquema:

![Post-acción para inspeccionar tests](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

Si estás usando [Mise](https://mise.jdx.dev/), tu script necesitará activar `tuist` en el entorno de la post-acción:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise y rutas del proyecto**
>
> La variable de entorno `PATH` de tu entorno no se hereda en la post-acción del esquema, por lo que debes usar la ruta absoluta de Mise, que dependerá de cómo hayas instalado Mise. Además, no olvides heredar la configuración de compilación desde un objetivo de tu proyecto para poder ejecutar Mise desde el directorio al que apunta $SRCROOT.

Tus ejecuciones de tests ahora se rastrean siempre que hayas iniciado sesión en tu cuenta de Tuist. Puedes acceder a tus análisis de tests en el panel de control de Tuist y ver cómo evolucionan con el tiempo:

![Panel de control con análisis de tests](/images/guides/features/build-insights/tests-dashboard.png)

Además de las tendencias generales, también puedes profundizar en cada test individual, por ejemplo, al depurar fallos o tests lentos en la CI:

![Detalle del test](/images/guides/features/build-insights/test-detail.png)

## Proyectos generados {#generated-projects}

> [!NOTE]
> Los esquemas autogenerados incluyen automáticamente la post-acción `tuist inspect test`.

>
> Si no te interesa rastrear los análisis de tests en tus esquemas autogenerados, desactívalos mediante la opción de generación [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

Si estás usando proyectos generados con esquemas personalizados, puedes configurar post-acciones para los análisis de tests:

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

Si no estás usando Mise, tus scripts pueden simplificarse a:

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

Para rastrear los análisis de tests en la CI, deberás asegurarte de que tu CI esté <.localized_link href="/guides/integrations/continuous-integration#authentication">autenticada</.localized_link>.

Además, necesitarás:
- Usar el comando <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> al invocar acciones de `xcodebuild`.
- Añadir `-resultBundlePath` a tu invocación de `xcodebuild`.

Cuando `xcodebuild` prueba tu proyecto sin `-resultBundlePath`, no se generan los archivos de paquete de resultados necesarios. La post-acción `tuist inspect test` requiere estos archivos para analizar tus tests.

### Historial de Git {#git-history}

En la CI, Tuist también sube el historial de commits del checkout: los SHA de los commits, sus padres, las fechas de los commits y la rama en la que estaba la ejecución y la rama base de su pull request. No se suben contenidos de archivos, mensajes de commit ni autores. Esto es lo que indica a Tuist qué commits llegaron a tu rama predeterminada, por ejemplo, los que probó una cola de fusiones. Tuist lee el historial que ya tiene el checkout y, cuando el checkout no tiene la rama base, solicita al remoto su último commit (`git ls-remote`). Fuera de la cobertura de código, no obtiene el historial.

| Variable | Efecto |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | No lee ni sube ningún historial de Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Lee solo el checkout, sin contactar con el remoto. |
