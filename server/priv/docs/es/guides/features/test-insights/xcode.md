---
{
  "title": "Xcode Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Xcode test analytics to identify slow and flaky tests with Tuist Test Insights."
}
---
# Información de tests de Xcode {#xcode-test-insights}

Tuist Test Insights te ofrece análisis de tests de Xcode para monitorizar la salud de tu suite de tests identificando tests lentos o comprendiendo rápidamente las ejecuciones de CI fallidas. A medida que tu suite de tests crece, resulta cada vez más difícil detectar tendencias como tests que se vuelven gradualmente más lentos o fallos intermitentes. Tuist Test Insights te proporciona la visibilidad que necesitas para mantener una suite de tests rápida y fiable.

Con Test Insights, puedes responder a preguntas como:
- ¿Se han vuelto mis tests más lentos? ¿Cuáles?
- ¿Qué tests son inestables y necesitan atención?
- ¿Por qué falló mi ejecución de CI?

## Configuración {#setup}

Para empezar a rastrear tus tests, puedes aprovechar el comando `tuist inspect test` añadiéndolo a la post-acción de test de tu esquema:

![Post-acción para inspeccionar tests](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

En caso de que estés usando [Mise](https://mise.jdx.dev/), tu script necesitará activar `tuist` en el entorno de la post-acción:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise y rutas del proyecto**
>
> La variable de entorno `PATH` de tu entorno no se hereda por la post-acción del esquema, y por lo tanto tienes que usar la ruta absoluta de Mise, que dependerá de cómo hayas instalado Mise. Además, no olvides heredar la configuración de compilación desde un objetivo en tu proyecto para que puedas ejecutar Mise desde el directorio apuntado por $SRCROOT.

Tus ejecuciones de tests ahora se rastrean siempre que hayas iniciado sesión en tu cuenta de Tuist. Puedes acceder a tu información de tests en el panel de control de Tuist y ver cómo evolucionan con el tiempo:

![Panel de control con información de tests](/images/guides/features/build-insights/tests-dashboard.png)

Además de las tendencias generales, también puedes profundizar en cada test individual, como al depurar fallos o tests lentos en la CI:

![Detalle del test](/images/guides/features/build-insights/test-detail.png)

## Proyectos generados {#generated-projects}

> [!NOTE]
> Los esquemas autogenerados incluyen automáticamente la post-acción `tuist inspect test`.

>
> Si no te interesa rastrear la información de tests en tus esquemas autogenerados, desactívalos usando la opción de generación [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

Si estás usando proyectos generados con esquemas personalizados, puedes configurar post-acciones para la información de tests:

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

Si no estás usando Mise, tus scripts se pueden simplificar a:

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

Para rastrear la información de tests en la CI, necesitarás asegurarte de que tu CI esté <.localized_link href="/guides/integrations/continuous-integration#authentication">autenticada</.localized_link>.

Adicionalmente, necesitarás either:
- Usar el comando <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> al invocar acciones de `xcodebuild`.
- Añadir `-resultBundlePath` a tu invocación de `xcodebuild`.

Cuando `xcodebuild` prueba tu proyecto sin `-resultBundlePath`, los archivos de paquete de resultados requeridos no se generan. La post-acción `tuist inspect test` requiere estos archivos para analizar tus tests.

### Historial de Git {#git-history}

En la CI, Tuist también sube el historial de commits del checkout: SHAs de commit, sus padres, fechas de commit y la rama en la que estaba la ejecución y su rama base de pull request. No se suben contenidos de archivos, mensajes de commit ni autores. Es lo que le indica a Tuist qué commits llegaron a tu rama predeterminada, por ejemplo, los que probó una cola de fusión. Tuist lee el historial que ya tiene el checkout, y cuando el checkout no tiene la rama base, solicita al remoto su último commit (`git ls-remote`). Fuera de la cobertura de código, no obtiene historial.

| Variable | Efecto |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | No lee ni sube ningún historial de Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Lee solo el checkout, sin contactar con el remoto. |
