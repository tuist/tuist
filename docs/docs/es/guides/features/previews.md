---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# Preestrenos {#previews}

> [REQUISITOS
> - A <LocalizedLink href="/guides/server/accounts-and-projects">Cuenta tuista y
>   proyecto</LocalizedLink>

Cuando creas una aplicación, es posible que quieras compartirla con otros para
obtener comentarios. Tradicionalmente, esto es algo que los equipos hacen
creando, firmando y enviando sus aplicaciones a plataformas como
[TestFlight](https://developer.apple.com/testflight/) de Apple. Sin embargo,
este proceso puede ser engorroso y lento, sobre todo cuando solo buscas la
opinión rápida de un colega o un amigo.

Para agilizar este proceso, Tuist ofrece una forma de generar y compartir vistas
previas de tus aplicaciones con cualquiera.

> [IMPORTANTE] LAS APLICACIONES CREADAS PARA DISPOSITIVOS DEBEN ESTAR FIRMADAS
> Cuando se crea una aplicación para un dispositivo, es responsabilidad del
> usuario asegurarse de que la aplicación está firmada correctamente. Tenemos
> previsto simplificarlo en el futuro.

:::grupo de códigos
```bash [Tuist Project]
tuist build App # Build the app for the simulator
tuist build App -- -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
:::

El comando generará un enlace que puedes compartir con cualquiera para que
ejecute la aplicación, ya sea en un simulador o en un dispositivo real. Todo lo
que tendrán que hacer es ejecutar el siguiente comando:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

Al compartir un archivo `.ipa`, puedes descargar la aplicación directamente
desde el dispositivo móvil utilizando el enlace Vista previa. Los enlaces a las
vistas previas de `.ipa` son por defecto _públicos_. En el futuro, tendrás la
opción de hacerlos privados, de modo que el destinatario del enlace tenga que
autenticarse con su cuenta de Tuist para descargar la app.

`tuist run` también le permite ejecutar una última vista previa basada en un
especificador como `latest`, nombre de rama o un hash de confirmación
específico:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [IMPORTANTE] VISIBILIDAD DE LAS PREVIAS Sólo las personas con acceso a la
> organización a la que pertenece el proyecto pueden acceder a las vistas
> previas. Tenemos previsto añadir soporte para enlaces que caducan.

## Aplicación Tuist para macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Para facilitar aún más la ejecución de Tuist Previews, hemos desarrollado una
aplicación de Tuist para la barra de menús de macOS. En lugar de ejecutar las
previsualizaciones a través de la CLI de Tuist, puedes
[descargar](https://tuist.dev/download) la aplicación para macOS. También puedes
instalar la aplicación ejecutando `brew install --cask tuist/tuist/tuist`.

Al hacer clic en "Ejecutar" en la página de vista previa, la aplicación macOS se
iniciará automáticamente en el dispositivo seleccionado.

> [REQUISITOS
> 
> Necesitas tener Xcode instalado localmente y estar en macOS 14 o posterior.

## Aplicación Tuist para iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

Al igual que la aplicación para macOS, las aplicaciones de Tuist para iOS
agilizan el acceso y la ejecución de tus previsualizaciones.

## Comentarios de solicitudes pull/merge {#pullmerge-request-comments}

> [IMPORTANTE] INTEGRACIÓN CON PLATAFORMA GIT REQUERIDA Para obtener comentarios
> automáticos en las solicitudes pull/merge, integra tu
> <LocalizedLink href="/guides/server/accounts-and-projects">proyecto
> remoto</LocalizedLink> con una
> <LocalizedLink href="/guides/server/authentication">plataforma
> Git</LocalizedLink>.

Probar nuevas funcionalidades debería formar parte de cualquier revisión de
código. Pero tener que compilar una aplicación localmente añade una fricción
innecesaria, que a menudo lleva a los desarrolladores a no probar la
funcionalidad en su dispositivo. Pero *¿y si cada pull request contuviera un
enlace a la compilación que ejecutaría automáticamente la aplicación en un
dispositivo seleccionado en la aplicación macOS de Tuist?*

Una vez que tu proyecto Tuist esté conectado con tu plataforma Git como
[GitHub](https://github.com), añade un <LocalizedLink href="/cli/share">`tuist
share MyApp`</LocalizedLink> a tu flujo de trabajo CI. Tuist entonces publicará
un enlace de Vista Previa directamente en tus pull requests: ![GitHub app
comment with a Tuist Preview
link](/images/guides/features/github-app-with-preview.png)

## Insignia README {#readme-badge}

Para que las Previsualizaciones de Tuist sean más visibles en tu repositorio,
puedes añadir una insignia a tu archivo `README` que apunte a la última
Previsualización de Tuist:

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Para añadir la insignia a su `README`, utilice el siguiente markdown y sustituya
los identificadores de cuenta y proyecto por los suyos propios:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Si tu proyecto contiene varias aplicaciones con diferentes identificadores de
paquete, puedes especificar a qué vista previa de aplicación enlazar añadiendo
un parámetro de consulta `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Automatizaciones {#automations}

Puede utilizar la bandera `--json` para obtener una salida JSON del comando
`tuist share`:
```
tuist share --json
```

La salida JSON es útil para crear automatizaciones personalizadas, como publicar
un mensaje de Slack utilizando su proveedor de CI. El JSON contiene una clave
`url` con el enlace a la vista previa completa y una clave `qrCodeURL` con la
URL a la imagen del código QR para facilitar la descarga de vistas previas desde
un dispositivo real. A continuación se muestra un ejemplo de salida JSON:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
