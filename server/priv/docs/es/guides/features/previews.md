---
{
  "title": "Previews",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Comparte compilaciones de apps para iOS y Android al instante con Tuist Previews. Ofrece a tus compañeros y partes interesadas un enlace, sin necesidad de configurar TestFlight ni Play Console."
}
---
# Previews {#previews}

Tuist Previews te permite generar y compartir vistas previas de apps para que tus compañeros puedan probar compilaciones sin tener que recompilar localmente.

Al compilar una app, es posible que quieras compartirla con otras personas para obtener feedback. Tradicionalmente, los equipos lo hacen compilando, firmando y enviando sus apps a plataformas como [TestFlight](https://developer.apple.com/testflight/) de Apple. Sin embargo, este proceso puede ser engorroso y lento, especialmente cuando solo buscas feedback rápido de un compañero o un amigo.

Para agilizar este proceso, Tuist ofrece una forma de generar y compartir vistas previas de tus apps con cualquier persona.

> [!WARNING]
> **Las compilaciones para dispositivo deben estar firmadas**
>
> Al compilar para dispositivo, actualmente es tu responsabilidad asegurarte de que la app esté firmada correctamente. Planeamos simplificar esto en el futuro.

::: code-group
```bash [Tuist Project (Debug)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Tuist Project (Release)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release
```
```bash [Xcode Project (Debug)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
```bash [Xcode Project (Release)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

El comando generará un enlace que puedes compartir con cualquiera para ejecutar la app, ya sea en un simulador o en un dispositivo real. Solo tendrán que ejecutar el siguiente comando:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

Al compartir un archivo `.ipa`, puedes descargar la app directamente desde el dispositivo móvil usando el enlace de Preview. Los enlaces a las vistas previas `.ipa` son _privados_ de forma predeterminada, lo que significa que el destinatario debe autenticarse con su cuenta de Tuist para descargar la app. Puedes cambiarlo a público en la configuración del proyecto si quieres compartir la app con cualquiera.

`tuist run` también te permite ejecutar la última vista previa basándote en un especificador como `latest`, el nombre de una rama o un hash de commit específico:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **Números de compilación únicos en CI**
>
> Asegúrate de que `CFBundleVersion` (versión de compilación) sea único aprovechando el número de ejecución de CI que exponen la mayoría de proveedores de CI. Por ejemplo, en GitHub Actions puedes establecer `CFBundleVersion` en la variable <code v-pre>${{ github.run_number }}</code>. 
>
> Subir una vista previa con el mismo binario (compilación) y el mismo `CFBundleVersion` fallará.

## Tracks {#tracks}

Los tracks te permiten organizar tus vistas previas en grupos con nombre. Por ejemplo, podrías tener un track `beta` para testers internos y un track `nightly` para compilaciones automatizadas. Los tracks se crean bajo demanda: simplemente especifica un nombre de track al compartir y se creará automáticamente si no existe.

Para compartir una vista previa en un track específico, usa la opción `--track`:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Esto es útil para:
- **Organizar vistas previas**: Agrupa las vistas previas por propósito (por ejemplo, `beta`, `nightly`, `internal`)
- **Actualizaciones dentro de la app**: El SDK de Tuist usa los tracks para determinar qué actualizaciones notificar a los usuarios
- **Filtrado**: Encuentra y gestiona fácilmente las vistas previas por track en el dashboard de Tuist

> [!WARNING]
> **Visibilidad de las vistas previas**
>
> Solo las personas con acceso a la organización a la que pertenece el proyecto pueden acceder a las vistas previas. Planeamos añadir soporte para enlaces con caducidad.

## Notas de la versión {#release-notes}

Usa los tracks para grupos de entornos y las notas de la versión para el propósito de una compilación individual:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

Las notas de la versión son texto plano opcional, de hasta 10.000 caracteres. La primera línea no vacía aparece como un fragmento de una sola línea en las listas de vistas previas web e iOS, de modo que los números de compilación y otra información identificativa son visibles de un vistazo. Las líneas largas se truncarán; las notas completas aparecen en las páginas de detalle. La búsqueda en ambas listas coincide con los nombres para mostrar y las notas de la versión completas, incluidas las líneas que no se muestran en el fragmento. Se admiten notas multilínea, por ejemplo `--release-notes "$(< release-notes.txt)"`. No cambian el nombre para mostrar de la app ni su track.

### Compatibilidad {#preview-metadata-compatibility}

Las notas de la versión son metadatos aditivos, no forman parte de la identidad de una vista previa. Las subidas desde clientes antiguos y nuevos siguen agrupándose en la misma vista previa entre plataformas. Se conservan las primeras notas no vacías: una subida posterior puede rellenar notas que antes faltaban, pero no puede sobrescribir notas existentes. Omitir `release_notes`, enviar `null` o enviar una cadena vacía o solo con espacios en blanco nunca borra las notas. Las vistas previas existentes no se rellenan retroactivamente y siguen siendo válidas sin notas.

El parámetro de consulta opcional `track` de la API de listado coincide con el nombre completo de un track, sin distinguir mayúsculas y minúsculas, de forma coherente con el almacenamiento existente de tracks. Omítelo o envía un valor vacío (`?track=`) para listar todos los tracks. Los nombres de los tracks siguen siendo cadenas abiertas, no una lista fija de valores. La selección **Todos los tracks** de la app de iOS omite el filtro. Las píldoras de track de la app de iOS cargan el resumen completo del proyecto desde `GET /api/projects/:account_handle/:project_handle/previews/tracks`, con la misma autorización de lectura de vistas previas que el listado de compilaciones. Ese endpoint devuelve `{total_count, tracks: [{name, count}]}` con los tracks nombrados ordenados y agrupados sin distinguir mayúsculas y minúsculas. Los recuentos cubren todo el proyecto independientemente de la paginación, la búsqueda y el track seleccionado; el total incluye vistas previas sin track. Solo se cuentan las vistas previas listables con un identificador de bundle. La API de listado también acepta el parámetro opcional `search` para una subcadena literal, sin distinguir mayúsculas y minúsculas, del nombre para mostrar o de las notas de la versión completas, combinado con el track antes de la paginación. El filtrado existente por `display_name` sigue siendo exacto.

Los clientes antiguos pueden seguir subiendo y listando vistas previas sin enviar ninguno de estos campos. Los clientes nuevos aceptan respuestas antiguas que omiten el track o las notas, e ignoran propiedades de respuesta desconocidas añadidas por servidores futuros. Las integraciones de API también deberían ignorar las propiedades de respuesta desconocidas para que los metadatos aditivos sigan siendo compatibles.

Los despliegues autoalojados necesitan una versión del servidor que admita notas de la versión y filtrado por track, junto con una CLI y una app actualizadas, para usar estas funcionalidades. Los servidores más antiguos pueden ignorar las notas o los parámetros de consulta desconocidos. Si el descubrimiento de tracks no está disponible, la app de iOS mantiene la navegación sin filtros disponible y explica que seleccionar un track requiere un servidor actualizado. Si un servidor devuelve vistas previas de otro track a pesar de tener un filtro activo, la app de iOS informa de que el filtrado no es compatible en lugar de presentar resultados engañosos. La app de macOS solicita primero la última vista previa compatible por app; en servidores más antiguos que seleccionan apps distintas antes de aplicar filtros de plataforma, recurre al historial paginado sin imponer un límite que podría ocultar una compilación disponible.

## App de Tuist para macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Para facilitar aún más la ejecución de Tuist Previews, hemos desarrollado una app de menú de Tuist para macOS. En lugar de ejecutar Previews mediante la CLI de Tuist, puedes [descargar](https://tuist.dev/download) la app para macOS. También puedes instalar la app ejecutando `brew install --cask tuist/tuist/tuist`.

Cuando hagas clic en "Ejecutar" en la página de vista previa, la app para macOS la lanzará automáticamente en el dispositivo que tengas seleccionado actualmente.

## App de Tuist para iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Descargar en el App Store" style="height: 40px;">
    </a>
</div>

Al igual que la app para macOS, la app de Tuist para iOS agiliza el acceso y la ejecución de tus vistas previas. Cada vista previa muestra su track. Usa el campo de búsqueda nativo para encontrar vistas previas por nombre de app y luego selecciona una píldora bajo **Tracks** para filtrar por entorno. La píldora seleccionada es morada; elige **Todas** para eliminar el filtro de track. Cada píldora muestra el recuento de vistas previas de todo el proyecto, y Todas incluye compilaciones sin un track. La búsqueda y el filtrado por track se aplican entre páginas, no solo a las vistas previas ya cargadas. La etiqueta de track de cada compilación aparece junto a su hash de commit.

## Comentarios en solicitudes de extracción/fusión {#pullmerge-request-comments}

> [!WARNING]
> **Se requiere integración con plataforma Git**
>
> Para obtener comentarios automáticos en las solicitudes de extracción/fusión, integra tu <.localized_link href="/guides/server/accounts-and-projects">proyecto remoto</.localized_link> con una <.localized_link href="/guides/server/authentication">plataforma Git</.localized_link>.

Probar nuevas funcionalidades debería formar parte de cualquier revisión de código. Pero tener que compilar una app localmente añade fricción innecesaria, lo que a menudo lleva a los desarrolladores a omitir por completo las pruebas de funcionalidad en sus dispositivos. Pero *¿y si cada solicitud de extracción contuviera un enlace a la compilación que ejecutaría automáticamente la app en un dispositivo que hayas seleccionado en la app de Tuist para macOS?*

Una vez que tu proyecto de Tuist esté conectado con tu plataforma Git, como [GitHub](https://github.com), añade un <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> a tu flujo de trabajo de CI. Tuist publicará entonces un enlace de vista previa directamente en tus solicitudes de extracción: ![Comentario de la app de GitHub con un enlace de vista previa de Tuist](/images/guides/features/github-app-with-preview.png)

## Notificaciones de actualización en la app {#in-app-update-notifications}

El [Tuist SDK](https://github.com/tuist/sdk) permite que tu app detecte cuando hay disponible una versión más reciente de la vista previa y notifique a los usuarios. Esto es útil para mantener a los testers en la última compilación.

El SDK busca actualizaciones dentro del mismo **track de vista previa**. Cuando compartes una vista previa con un track explícito usando `--track`, el SDK buscará actualizaciones en ese track. Si no se especifica ningún track, se usa la rama de git como track, por lo que una vista previa compilada desde la rama `main` solo notificará sobre vistas previas más recientes también compiladas desde `main`.

### Instalación {#sdk-installation}

Añade el Tuist SDK como dependencia de Swift Package:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Supervisar actualizaciones {#sdk-monitor-updates}

Usa `monitorPreviewUpdates` para comprobar periódicamente si hay nuevas versiones de vista previa:

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

### Comprobación única de actualización {#sdk-single-check}

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

`monitorPreviewUpdates` devuelve una `Task` que se puede cancelar:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> La comprobación de actualizaciones se desactiva automáticamente en simuladores y compilaciones del App Store.

## Insignia del README {#readme-badge}

Para hacer que Tuist Previews sea más visible en tu repositorio, puedes añadir una insignia a tu archivo `README` que apunte a la última vista previa de Tuist:

[![Vista previa de Tuist](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Para añadir la insignia a tu `README`, usa el siguiente markdown y reemplaza los identificadores de cuenta y proyecto con los tuyos:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Si tu proyecto contiene varias apps con diferentes identificadores de bundle, puedes especificar a qué vista previa de app enlazar añadiendo un parámetro de consulta `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Automatizaciones {#automations}

Puedes usar la bandera `--json` para obtener una salida JSON del comando `tuist share`:
```
tuist share --json
```

La salida JSON es útil para crear automatizaciones personalizadas, como publicar un mensaje en Slack usando tu proveedor de CI. El JSON contiene una clave `url` con el enlace completo a la vista previa y una clave `qrCodeURL` con la URL de la imagen del código QR para facilitar la descarga de vistas previas desde un dispositivo real. A continuación se muestra un ejemplo de salida JSON:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
