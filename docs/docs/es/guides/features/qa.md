---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# CONTROL DE CALIDAD {#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA está actualmente en fase de vista previa. Regístrate en
[tuist.dev/qa](https://tuist.dev/qa) para obtener acceso.
<!-- -->
:::

El desarrollo de aplicaciones móviles de calidad se basa en pruebas exhaustivas,
pero los enfoques tradicionales tienen limitaciones. Las pruebas unitarias son
rápidas y rentables, pero no tienen en cuenta las situaciones reales de los
usuarios. Las pruebas de aceptación y el control de calidad manual pueden cubrir
estas lagunas, pero consumen muchos recursos y no son escalables.

El agente de control de calidad de Tuist resuelve este problema simulando el
comportamiento real de los usuarios. Explora tu aplicación de forma autónoma,
reconoce elementos de la interfaz, ejecuta interacciones realistas y señala
posibles problemas. Este enfoque le ayuda a identificar errores y problemas de
usabilidad en las primeras fases del desarrollo, al tiempo que evita la
sobrecarga y el mantenimiento de las pruebas convencionales de aceptación y
control de calidad.

## Requisitos previos {#prerequisites}

Para empezar a utilizar Tuist QA, necesitas:
- Configure la carga de
  <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink> desde
  su flujo de trabajo PR CI, que el agente puede utilizar para realizar pruebas.
- <LocalizedLink href="/guides/integrations/gitforge/github">Integra</LocalizedLink>
  con GitHub, para que puedas activar el agente directamente desde tu PR.

## Uso {#usage}

Actualmente, Tuist QA se activa directamente desde un PR. Una vez que tengas una
vista previa asociada a tu PR, puedes activar el agente de QA comentando `/qa
test I want to test feature A` en el PR:

(/images/guides/features/qa/qa-trigger-comment.png)[QA trigger
comment](/images/guides/features/qa/qa-trigger-comment.png)

El comentario incluye un enlace a la sesión en directo, donde podrá ver en
tiempo real el progreso del agente de control de calidad y cualquier problema
que encuentre. Una vez que el agente complete su ejecución, publicará un resumen
de los resultados en el RP:

[Resumen de la prueba de control de
calidad](/images/guides/features/qa/qa-test-summary.png)

Como parte del informe del panel de control, al que enlaza el comentario de
relaciones públicas, obtendrá una lista de problemas y una cronología, para que
pueda inspeccionar cómo se produjo exactamente el problema:

(/images/guides/features/qa/qa-timeline.png)[Cronología de la
GC](/images/guides/features/qa/qa-timeline.png)

Puede ver todas las ejecuciones de control de calidad que realizamos para
nuestra <LocalizedLink href="/guides/features/previews#tuist-ios-app">aplicación iOS</LocalizedLink> en nuestro panel público: https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
El agente de control de calidad se ejecuta de forma autónoma y no puede ser
interrumpido con avisos adicionales una vez iniciado. Proporcionamos registros
detallados durante la ejecución para ayudarle a comprender cómo interactuó el
agente con su aplicación. Estos registros son valiosos para iterar sobre el
contexto de su aplicación y probar las instrucciones para guiar mejor el
comportamiento del agente. Si tiene algún comentario sobre cómo funciona el
agente con su aplicación, háganoslo saber a través de [GitHub
Issues](https://github.com/tuist/tuist/issues), nuestra [comunidad
Slack](https://slack.tuist.dev) o nuestro [foro de la
comunidad](https://community.tuist.dev).
<!-- -->
:::

### Contexto de la aplicación {#app-context}

El agente puede necesitar más contexto sobre tu app para poder navegar bien por
ella. Tenemos tres tipos de contexto de aplicación:
- Descripción de la aplicación
- Credenciales
- Lanzar grupos de discusión

Todos ellos pueden configurarse en los ajustes del panel de control de su
proyecto (`Settings` > `QA`).

#### Descripción de la aplicación {#app-description}

La descripción de la aplicación sirve para proporcionar contexto adicional sobre
lo que hace su aplicación y cómo funciona. Se trata de un campo de texto largo
que se pasa como parte de la solicitud al iniciar el agente. Un ejemplo podría
ser:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### Credenciales {#credentials}

En caso de que el agente necesite iniciar sesión en la aplicación para probar
algunas funciones, puede proporcionarle credenciales para que las utilice. El
agente rellenará estas credenciales si reconoce que necesita iniciar sesión.

#### Lanzar grupos de discusión {#launch-argument-groups}

Los grupos de argumentos de lanzamiento se seleccionan en función de su
solicitud de prueba antes de ejecutar el agente. Por ejemplo, si no quieres que
el agente inicie sesión repetidamente, malgastando tus tokens y minutos de
ejecución, puedes especificar aquí tus credenciales. Si el agente reconoce que
debe iniciar la sesión con sesión iniciada, utilizará el grupo de argumentos de
lanzamiento de credenciales al iniciar la aplicación.

[Lanzar grupos de
argumentos](/images/guides/features/qa/launch-argument-groups.png)

Estos argumentos de inicio son los argumentos estándar de Xcode. Aquí tienes un
ejemplo de cómo usarlos para iniciar sesión automáticamente:

```swift
import ArgumentParser
import SwiftUI

@main
struct TuistApp: App {
    var body: some Scene {
        ContentView()
        #if DEBUG
            .task {
                await checkForAutomaticLogin()
            }
        #endif
    }
    /// When launch arguments with credentials are passed, such as when running QA tests, we can skip the log in and
    /// automatically log in
    private func checkForAutomaticLogin() async {
        struct LaunchArguments: ParsableArguments {
            @Option var email: String?
            @Option var password: String?
        }

        do {
            let parsedArguments = try LaunchArguments.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))

            guard let email = parsedArguments.email,
                  let password = parsedArguments.password
            else {
                return
            }

            try await authenticationService.signInWithEmailAndPassword(email: email, password: password)
        } catch {
            // Skipping automatic log in
        }
    }
}
```
