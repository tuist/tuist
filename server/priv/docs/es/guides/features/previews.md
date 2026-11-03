---
{
  "title": "Previews",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Comparte apps móviles, apps de escritorio y herramientas de línea de comandos con Tuist Previews para que tus compañeros puedan probar una compilación sin tener que recompilarla localmente."
}
---
# Previews {#previews}

Tuist Previews permite que tus compañeros prueben apps móviles, apps de escritorio y herramientas de línea de comandos sin tener que compilarlas localmente. Publica una compilación en tu proyecto de Tuist y comparte el enlace de la vista previa.

## Qué puedes previsualizar {#what-you-can-preview}

- **Apps móviles:** APKs de Android y paquetes de aplicación de Apple o IPAs. Los dispositivos compatibles, los simuladores y los requisitos de firma dependen del flujo de publicación.
- **Apps de escritorio:** Paquetes de aplicación de macOS.
- **Herramientas de línea de comandos:** Ejecutables de macOS o Linux, por sí solos o empaquetados con sus dependencias.

Consulta <.localized_link href="/guides/features/previews/types">Tipos compatibles</.localized_link> para conocer los requisitos de empaquetado y compatibilidad. El tipo de artefacto determina dónde se puede ejecutar una vista previa; no dicta qué sistema de compilación lo produce.

## Publicar una vista previa {#publish-a-preview}

Elige tu sistema de compilación para los comandos de configuración y publicación:

<.home_cards>
  <.home_card
    title="Xcode"
    details="Comparte aplicaciones desde proyectos de Xcode existentes o proyectos generados por Tuist."
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="Comparte apps de Android y herramientas nativas de línea de comandos desde proyectos de Gradle."
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="Comparte apps de Android, apps de Apple y herramientas de línea de comandos con reglas complementarias de Bazel."
    link="/guides/features/previews/bazel"
  />
</.home_cards>

Si ya tienes una compilación compatible, usa <.localized_link href="/cli/share">`tuist share`</.localized_link> para publicarla sin una integración con el sistema de compilación. Siguen aplicándose los requisitos de empaquetado y firma.

## Ejecutar una vista previa {#run-a-preview}

Los destinatarios no necesitan el sistema de compilación que produjo la vista previa. Elige cómo acceder a una compilación compatible:

<.home_cards>
  <.home_card
    title="CLI"
    details="Ejecuta apps móviles, apps de macOS y vistas previas de línea de comandos con tuist run."
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="App de macOS"
    details="Ejecuta vistas previas compatibles de Apple a través de la app de la barra de menús de Tuist."
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="App de iPhone"
    details="Encuentra y accede a tus vistas previas de Apple en el iPhone."
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## Visibilidad {#visibility}

Las vistas previas usan la visibilidad predeterminada del proyecto. Las vistas previas privadas requieren autenticación y acceso al proyecto. Haz públicas las vistas previas en la configuración del proyecto solo cuando la compilación pueda compartirse con cualquiera. La visibilidad pública no omite los requisitos de firma de la plataforma ni de instalación en el dispositivo.

## Canales {#tracks}

Los canales organizan las vistas previas en grupos con nombre, como `beta` para testers internos o `nightly` para compilaciones automatizadas. Especifica un canal con el comando de publicación para tu flujo de trabajo; los canales se crean bajo demanda la primera vez que se usan. Úsalos para agrupar vistas previas por propósito y filtrarlas en el dashboard de Tuist.

## Insignia para README {#readme-badge}

Añade una insignia al `README` de tu repositorio que apunte a la última vista previa:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Reemplaza los identificadores de cuenta y proyecto con los tuyos:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Si el proyecto contiene varias apps con diferentes identificadores de paquete, añade un parámetro de consulta `bundle-id` para elegir la app:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
