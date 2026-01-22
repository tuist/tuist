---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# Vistas previas {#previews}

::: advertencia REQUISITOS
<!-- -->
- Una cuenta y un proyecto
  <LocalizedLink href="/guides/server/accounts-and-projects">Tuist.</LocalizedLink>
<!-- -->
:::

Al crear una aplicación, es posible que desee compartirla con otras personas
para obtener comentarios. Tradicionalmente, esto es algo que los equipos hacen
creando, firmando y enviando sus aplicaciones a plataformas como
[TestFlight](https://developer.apple.com/testflight/) de Apple. Sin embargo,
este proceso puede ser engorroso y lento, especialmente cuando solo se busca
obtener comentarios rápidos de un colega o amigo.

Para agilizar este proceso, Tuist ofrece una forma de generar y compartir vistas
previas de tus aplicaciones con cualquier persona.

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
Al crear para un dispositivo, actualmente es su responsabilidad asegurarse de
que la aplicación esté firmada correctamente. Tenemos previsto simplificar este
proceso en el futuro.
<!-- -->
:::

::: grupo de códigos
```bash [Tuist Project]
tuist generate App
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

El comando generará un enlace que podrás compartir con cualquier persona para
ejecutar la aplicación, ya sea en un simulador o en un dispositivo real. Todo lo
que tendrán que hacer es ejecutar el siguiente comando:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

Al compartir un archivo `.ipa`, puede descargar la aplicación directamente desde
el dispositivo móvil utilizando el enlace de vista previa. Los enlaces a las
vistas previas de `.ipa` son, por defecto, _privados_, lo que significa que el
destinatario debe autenticarse con su cuenta de Tuist para descargar la
aplicación. Puede cambiar esto a público en la configuración del proyecto si
desea compartir la aplicación con cualquier persona.

`tuist run` también te permite ejecutar una vista previa más reciente basada en
un especificador como `latest`, nombre de la rama o un hash de confirmación
específico:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
Asegúrate de que `CFBundleVersion` (versión de compilación) sea único utilizando
un número de ejecución de CI que la mayoría de los proveedores de CI exponen.
Por ejemplo, en GitHub Actions puedes establecer `CFBundleVersion` en la
variable <code v-pre>${{ github.run_number }}</code>.

La carga de una vista previa con el mismo binario (compilación) y el mismo
`CFBundleVersion` fallará.
<!-- -->
:::

## Pistas {#tracks}

Las pistas te permiten organizar tus vistas previas en grupos con nombre. Por
ejemplo, puedes tener una pista `beta` para probadores internos y una pista
`nightly` para compilaciones automatizadas. Las pistas se crean de forma
diferida: solo tienes que especificar un nombre de pista al compartir y se
creará automáticamente si no existe.

Para compartir una vista previa de una pista específica, utiliza la opción
`--track`:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Esto es útil para:
- **Organizar vistas previas**: Agrupar las vistas previas por finalidad (por
  ejemplo, `beta`, `nightly`, `internal`)
- **Actualizaciones en la aplicación**: El SDK de Tuist utiliza pistas para
  determinar qué actualizaciones notificar a los usuarios.
- **Filtrado de**: Encuentre y gestione fácilmente las vistas previas por pista
  en el panel de control de Tuist.

::: warning PREVIEWS' VISIBILITY
<!-- -->
Solo las personas con acceso a la organización a la que pertenece el proyecto
pueden acceder a las vistas previas. Tenemos previsto añadir compatibilidad con
enlaces caducados.
<!-- -->
:::

## Aplicación Tuist para macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Para facilitar aún más la ejecución de Tuist Previews, hemos desarrollado una
aplicación Tuist para la barra de menú de macOS. En lugar de ejecutar Previews a
través de la CLI de Tuist, puedes [descargar](https://tuist.dev/download) la
aplicación para macOS. También puedes instalar la aplicación ejecutando `brew
install --cask tuist/tuist/tuist`.

Ahora, cuando hagas clic en «Ejecutar» en la página de vista previa, la
aplicación macOS lo iniciará automáticamente en el dispositivo seleccionado
actualmente.

::: advertencia REQUISITOS
<!-- -->
Debes tener Xcode instalado localmente y utilizar macOS 14 o posterior.
<!-- -->
:::

## Aplicación Tuist para iOS. {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

Al igual que la aplicación para macOS, las aplicaciones Tuist para iOS agilizan
el acceso y la ejecución de las vistas previas.

## Comentarios sobre solicitudes de extracción/fusión {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Para obtener comentarios automáticos de solicitudes de extracción/fusión,
integra tu <LocalizedLink href="/guides/server/accounts-and-projects">proyecto
remoto</LocalizedLink> con una
<LocalizedLink href="/guides/server/authentication">plataforma
Git</LocalizedLink>.
<!-- -->
:::

Probar las nuevas funcionalidades debería formar parte de cualquier revisión de
código. Sin embargo, tener que crear una aplicación localmente añade una
fricción innecesaria, lo que a menudo lleva a los desarrolladores a saltarse por
completo la prueba de funcionalidades en su dispositivo. Pero, ¿ *, qué pasaría
si cada solicitud de extracción contuviera un enlace a la compilación que
ejecutara automáticamente la aplicación en un dispositivo seleccionado en la
aplicación Tuist para macOS?*

Una vez que tu proyecto Tuist esté conectado con tu plataforma Git, como
[GitHub](https://github.com), añade <LocalizedLink href="/cli/share">`tuist
share MyApp`</LocalizedLink> a tu flujo de trabajo de CI. Tuist publicará
entonces un enlace de vista previa directamente en tus solicitudes de
extracción: ![Comentario de la aplicación GitHub con un enlace de vista previa
de Tuist](/images/guides/features/github-app-with-preview.png)


## Notificaciones de actualización en la aplicación. {#in-app-update-notifications}

El [Tuist SDK](https://github.com/tuist/sdk) permite a tu aplicación detectar
cuándo hay disponible una versión preliminar más reciente y notificarlo a los
usuarios. Esto resulta útil para mantener a los probadores con la última
versión.

El SDK comprueba si hay actualizaciones dentro de la misma pista de vista previa
**** . Cuando compartes una vista previa con una pista explícita utilizando
`--track`, el SDK buscará actualizaciones en esa pista. Si no se especifica
ninguna pista, se utiliza la rama git como pista, por lo que una vista previa
creada a partir de la rama principal `` solo notificará las vistas previas más
recientes creadas también a partir de la rama principal `` .

### Instalación {#sdk-installation}

Añade Tuist SDK como dependencia del paquete Swift:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Supervisar las actualizaciones. {#sdk-monitor-updates}

Utilice `monitorPreviewUpdates` para comprobar periódicamente si hay nuevas
versiones de vista previa:

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### Comprobación de actualización única. {#sdk-single-check}

Para la comprobación manual de actualizaciones:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### Detener la supervisión de actualizaciones {#sdk-stop-monitoring}

`monitorPreviewUpdates` devuelve una tarea `` que se puede cancelar:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
La comprobación de actualizaciones se desactiva automáticamente en los
simuladores y en las compilaciones de la App Store.
<!-- -->
:::

## Insignia README {#readme-badge}

Para que las vistas previas de Tuist sean más visibles en tu repositorio, puedes
añadir una insignia a tu archivo README `` que apunte a la última vista previa
de Tuist:

[![Vista previa de
Tuist](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Para añadir la insignia a tu README de `` , utiliza el siguiente marcado y
sustituye los nombres de usuario y del proyecto por los tuyos propios:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Si tu proyecto contiene varias aplicaciones con diferentes identificadores de
paquete, puedes especificar a qué vista previa de la aplicación enlazar
añadiendo un parámetro de consulta `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Automatizaciones {#automations}

Puede utilizar el indicador `--json` para obtener una salida JSON del comando
`tuist share`:
```
tuist share --json
```

La salida JSON es útil para crear automatizaciones personalizadas, como publicar
un mensaje de Slack utilizando tu proveedor de CI. El JSON contiene una clave
`url` con el enlace de vista previa completo y una clave `qrCodeURL` con la URL
de la imagen del código QR para facilitar la descarga de vistas previas desde un
dispositivo real. A continuación se muestra un ejemplo de salida JSON:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
