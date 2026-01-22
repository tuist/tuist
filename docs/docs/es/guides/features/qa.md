---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# Control de calidad {#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA se encuentra actualmente en fase de previsualización inicial.
Regístrate en [tuist.dev/qa](https://tuist.dev/qa) para obtener acceso.
<!-- -->
:::

El desarrollo de aplicaciones móviles de calidad se basa en pruebas exhaustivas,
pero los enfoques tradicionales tienen limitaciones. Las pruebas unitarias son
rápidas y rentables, pero no reflejan los escenarios reales de los usuarios. Las
pruebas de aceptación y el control de calidad manual pueden subsanar estas
deficiencias, pero requieren muchos recursos y no son fácilmente escalables.

El agente de control de calidad de Tuist resuelve este reto simulando el
comportamiento auténtico de los usuarios. Explora de forma autónoma su
aplicación, reconoce los elementos de la interfaz, ejecuta interacciones
realistas y señala posibles problemas. Este enfoque le ayuda a identificar
errores y problemas de usabilidad en las primeras fases del desarrollo, al
tiempo que evita la sobrecarga y el mantenimiento que suponen las pruebas de
aceptación y control de calidad convencionales.

## Requisitos previos {#prerequisites}

Para empezar a utilizar Tuist QA, debes:
- Configura la carga de
  <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink> desde
  tu flujo de trabajo PR CI, que el agente podrá utilizar para realizar pruebas.
- <LocalizedLink href="/guides/integrations/gitforge/github">Integra</LocalizedLink>
  con GitHub, para que puedas activar el agente directamente desde tu PR.

## Uso {#usage}

Tuist QA se activa actualmente directamente desde una PR. Una vez que tengas una
vista previa asociada a tu PR, puedes activar el agente de control de calidad
comentando `/qa test Quiero probar la función A` en la PR:

![Comentario de activación de control de
calidad](/images/guides/features/qa/qa-trigger-comment.png)

El comentario incluye un enlace a la sesión en vivo, donde se puede ver en
tiempo real el progreso del agente de control de calidad y cualquier problema
que encuentre. Una vez que el agente complete su ejecución, publicará un resumen
de los resultados en la solicitud de incorporación de cambios:

![Resumen de la prueba de control de
calidad](/images/guides/features/qa/qa-test-summary.png)

Como parte del informe del panel, al que enlaza el comentario de relaciones
públicas, obtendrá una lista de incidencias y una cronología, de modo que podrá
inspeccionar cómo se produjo exactamente la incidencia:

![Cronología de control de calidad](/images/guides/features/qa/qa-timeline.png)

Puedes ver todas las pruebas de control de calidad que realizamos para nuestra
<LocalizedLink href="/guides/features/previews#tuist-ios-app">aplicación
iOS</LocalizedLink> en nuestro panel de control público:
https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
El agente de control de calidad funciona de forma autónoma y, una vez iniciado,
no se puede interrumpir con indicaciones adicionales. Proporcionamos registros
detallados durante toda la ejecución para ayudarle a comprender cómo interactuó
el agente con su aplicación. Estos registros son valiosos para iterar en el
contexto de su aplicación y probar indicaciones para guiar mejor el
comportamiento del agente. Si tiene comentarios sobre el rendimiento del agente
con su aplicación, háganoslo saber a través de [GitHub
Issues](https://github.com/tuist/tuist/issues), nuestra [comunidad
Slack](https://slack.tuist.dev) o nuestro [foro
comunitario](https://community.tuist.dev).
<!-- -->
:::

### Contexto de la aplicación {#app-context}

Es posible que el agente necesite más contexto sobre tu aplicación para poder
navegar bien por ella. Tenemos tres tipos de contexto de aplicación:
- Descripción de la aplicación
- Credenciales
- Grupos de argumentos de inicio

Todo esto se puede configurar en los ajustes del panel de control de tu proyecto
(`Ajustes` > `QA`).

#### Descripción de la aplicación {#app-description}

La descripción de la aplicación sirve para proporcionar contexto adicional sobre
lo que hace tu aplicación y cómo funciona. Se trata de un campo de texto largo
que se pasa como parte de la indicación al iniciar el agente. Un ejemplo podría
ser:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### Credenciales {#credentials}

En caso de que el agente necesite iniciar sesión en la aplicación para probar
algunas funciones, puede proporcionarle las credenciales para que las utilice.
El agente rellenará estas credenciales si reconoce que necesita iniciar sesión.

#### Grupos de argumentos de inicio {#launch-argument-groups}

Los grupos de argumentos de inicio se seleccionan en función de la indicación de
prueba antes de ejecutar el agente. Por ejemplo, si no desea que el agente
inicie sesión repetidamente, desperdiciando sus tokens y minutos de ejecución,
puede especificar aquí sus credenciales. Si el agente reconoce que debe iniciar
la sesión con la sesión iniciada, utilizará el grupo de argumentos de inicio de
credenciales al iniciar la aplicación.

![Grupos de argumentos de
lanzamiento](/images/guides/features/qa/launch-argument-groups.png)

Estos argumentos de inicio son los argumentos de inicio estándar de Xcode. A
continuación se muestra un ejemplo de cómo utilizarlos para iniciar sesión
automáticamente:

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
