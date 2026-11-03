---
{
  "title": "Ejecutar vistas previas con la app para iPhone",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Encuentra, filtra y accede a las vistas previas de Apple con la app de Tuist para iOS."
}
---
# Ejecuta previews con la app de iPhone

Instala la [app de Tuist para iOS desde la App Store](https://apps.apple.com/us/app/tuist/id6748460335) para encontrar y acceder a tus previews de Apple. Siguen aplicándose los requisitos de firma y elegibilidad de dispositivos del flujo de publicación.

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Descargar en la App Store" style="height: 40px;">
    </a>
</div>

Busca por nombre de la app o notas de la versión, luego selecciona un track para filtrar las previews. Elige **Todas** para navegar por todos los tracks, incluidas las previews sin track. Abre una preview para leer sus notas de la versión completas.

## Compatibilidad entre cliente y servidor {#client-and-server-compatibility}

Mantén la app de Tuist actualizada. Si alojas Tuist tú mismo, actualiza tu servidor para usar el filtrado por track y las notas de la versión. Aún puedes navegar por las previews sin filtrar en servidores antiguos.

## Notificaciones de actualización en la app {#in-app-update-notifications}

El [Tuist SDK](https://github.com/tuist/sdk) permite que tu app de Apple detecte una preview más reciente y notifique a los testers. Comprueba actualizaciones dentro del mismo **track de preview**. Para las previews publicadas con `tuist share --track`, usa ese track explícito. Sin un track explícito, se usa la rama de git, por lo que una preview compilada desde `main` solo notifica sobre previews más recientes de `main`.

### Instalación {#sdk-installation}

Añade el Tuist SDK como dependencia de Swift Package:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Monitorizar actualizaciones {#sdk-monitor-updates}

Usa `monitorPreviewUpdates` para comprobar periódicamente nuevas versiones de preview:

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

Para comprobar manualmente las actualizaciones:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### Detener la monitorización de actualizaciones {#sdk-stop-monitoring}

`monitorPreviewUpdates` devuelve un `Task` que se puede cancelar:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> La comprobación de actualizaciones se desactiva automáticamente en simuladores y builds de la App Store.
