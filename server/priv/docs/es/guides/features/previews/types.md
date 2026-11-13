---
{
  "title": "Tipos de vistas previas compatibles",
  "titleTemplate": ":title · Vistas previas · Tuist",
  "description": "Requisitos de empaquetado y compatibilidad para apps móviles, apps de macOS y vistas previas de línea de comandos."
}
---
# Tipos de vista previa compatibles

El tipo de vista previa determina qué empaquetas y dónde puede ejecutarse, independientemente del sistema de compilación que lo produzca. Cada flujo de publicación tiene sus propios requisitos de firma y elegibilidad.

## Aplicaciones móviles {#mobile-apps}

- **Android:** un APK de aplicación firmado. Los destinatarios necesitan un dispositivo Android o un emulador compatible. Los Android App Bundles (`.aab`) no son paquetes de instalación de vistas previas.
- **Apple:** un bundle de aplicación para un simulador, o una IPA exportada para dispositivos físicos. Las compilaciones para dispositivo necesitan un perfil de aprovisionamiento que permita la instalación en el dispositivo del destinatario.

Las guías de <.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>, <.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link> y <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link> describen qué salidas puede publicar cada flujo de trabajo. Por ejemplo, la publicación con Bazel y Once admite aplicaciones elegibles para el simulador de Apple y macOS, pero no compilaciones para dispositivos físicos.

## Aplicaciones de escritorio {#desktop-apps}

Comparte un bundle de aplicación de macOS compilado:

```bash
tuist share path/to/MyApp.app
```

Los requisitos de firma y notarización siguen aplicándose. Un bundle de aplicación de escritorio es diferente de la aplicación Tuist para macOS, que los destinatarios pueden usar para ejecutar vistas previas.

## Herramientas de línea de comandos {#command-line-tools}

Comparte un ejecutable independiente en macOS o Linux:

```bash
tuist share path/to/my-tool
```

Si la CLI necesita bundles de recursos, bibliotecas dinámicas o ejecutables auxiliares, ensambla un directorio de distribución y especifica su punto de entrada relativo a ese directorio:

```bash
tuist share path/to/distribution --executable bin/my-tool
```

Se sube el directorio de distribución completo. Incluye las bibliotecas, los recursos y los auxiliares que necesite tu herramienta, y asegúrate de que pueda ejecutarse fuera de tu directorio de compilación. Los scripts necesitan una shebang y un intérprete instalado en el sistema del destinatario.

## Múltiples destinos de CLI {#multiple-cli-targets}

Una vista previa agrupa compilaciones de la misma CLI para un único commit; cada compilación contiene una distribución para un sistema operativo y una o más arquitecturas de CPU. Por ejemplo, una vista previa puede contener distribuciones para macOS arm64, macOS x86_64 y Linux x86_64. Un ejecutable universal de macOS cubre ambas arquitecturas de Mac en una sola compilación.

Compila cada destino por separado y luego publica las distribuciones secuencialmente desde el mismo checkout de Git usando el mismo nombre base del punto de entrada y track:

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

Estas cargas añaden compilaciones al mismo enlace de vista previa. Mantén el proyecto, el commit, la cuenta de publicación, el nombre de la CLI y el track idénticos en todas las cargas. Tuist selecciona la compilación que coincide con el sistema operativo y la arquitectura de CPU del destinatario.

## Compatibilidad entre cliente y servidor {#client-and-server-compatibility}

Usa una versión actualizada de la CLI de Tuist para ejecutar vistas previas de escritorio y de línea de comandos. Si alojas Tuist tú mismo, actualiza tu servidor antes de publicar estos tipos. Las vistas previas móviles siguen funcionando con clientes anteriores.

Compila para los sistemas operativos y las arquitecturas de CPU de tus destinatarios. Tuist no realiza compilación cruzada de tu app ni instala sus dependencias; las herramientas de Linux también necesitan bibliotecas del sistema compatibles.

Las vistas previas se ejecutan con los permisos de tu cuenta de usuario, no en un sandbox. Ejecuta solo compilaciones de autores y pull requests en los que confíes.

Consulta <.localized_link href="/guides/features/previews/run/cli">Ejecutar vistas previas con la CLI</.localized_link> para conocer el comportamiento de ejecución y el reenvío de argumentos, y la <.localized_link href="/guides/features/previews#visibility">visión general de las vistas previas</.localized_link> para obtener información sobre acceso, tracks y badges de README.
