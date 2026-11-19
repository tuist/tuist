---
{
  "title": "Tipos de previsualización compatibles",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Requisitos de empaquetado y compatibilidad para aplicaciones móviles, aplicaciones de macOS y previsualizaciones de línea de comandos."
}
---
# Tipos de previsualización compatibles

El tipo de previsualización determina qué empaquetas y dónde puede ejecutarse, independientemente del sistema de compilación que lo produzca. Cada flujo de publicación tiene sus propios requisitos de firma y elegibilidad.

## Aplicaciones móviles {#mobile-apps}

- **Android:** un APK de aplicación firmado. Los destinatarios necesitan un dispositivo o emulador Android compatible. Los Android App Bundles (`.aab`) no son paquetes de instalación para previsualizaciones.
- **Apple:** un bundle de aplicación para el simulador, o una IPA exportada para dispositivos físicos. Las compilaciones para dispositivo necesitan un perfil de aprovisionamiento que permita la instalación en el dispositivo del destinatario.

Las guías de <.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>, <.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link> y <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link> describen qué salidas puede publicar cada flujo. Por ejemplo, la publicación con Bazel y Once admite aplicaciones elegibles para el simulador de Apple y macOS, pero no compilaciones para dispositivos físicos.

## Aplicaciones de escritorio {#desktop-apps}

Comparte un bundle de aplicación de macOS ya compilado:

```bash
tuist share path/to/MyApp.app
```

Los requisitos de firma y notalización siguen aplicándose. Un bundle de aplicación de escritorio es diferente de la app de Tuist para macOS, que los destinatarios pueden usar para ejecutar previsualizaciones.

## Herramientas de línea de comandos {#command-line-tools}

Comparte un ejecutable independiente en macOS o Linux:

```bash
tuist share path/to/my-tool
```

Si la CLI necesita bundles de recursos, bibliotecas dinámicas o ejecutables auxiliares, prepara un directorio de distribución y especifica su punto de entrada relativo a ese directorio:

```bash
tuist share path/to/distribution --executable bin/my-tool
```

Se sube el directorio de distribución completo. Incluye las bibliotecas, los recursos y los archivos auxiliares que necesite tu herramienta, y asegúrate de que pueda ejecutarse fuera de tu directorio de compilación. Los scripts necesitan una línea shebang y un intérprete instalado en el sistema del destinatario.

Los ejecutables no incluyen icono propio. Pasa un PNG con `--icon` para mostrar uno en la previsualización, por ejemplo para una app de escritorio en Linux:

```bash
tuist share path/to/distribution --executable bin/my-app --icon path/to/icon.png
```

## Múltiples destinos de CLI {#multiple-cli-targets}

Una previsualización agrupa compilaciones de la misma CLI para un único commit; cada compilación contiene una distribución para un sistema operativo y una o más arquitecturas de CPU. Por ejemplo, una previsualización puede contener distribuciones para macOS arm64, macOS x86_64 y Linux x86_64. Un ejecutable universal de macOS cubre ambas arquitecturas de Mac en una sola compilación.

Compila cada destino por separado y luego publica las distribuciones secuencialmente desde el mismo checkout de Git, usando el mismo nombre base del punto de entrada y la misma pista:

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

Estas subidas añaden compilaciones al mismo enlace de previsualización. Mantén el proyecto, el commit, la cuenta de publicación, el nombre de la CLI y la pista idénticos en todas las subidas. Tuist selecciona la compilación que coincide con el sistema operativo y la arquitectura de CPU del destinatario.

## Compatibilidad entre cliente y servidor {#client-and-server-compatibility}

Usa una versión actualizada de la CLI de Tuist para ejecutar previsualizaciones de escritorio y de línea de comandos. Si alojas Tuist tú mismo, actualiza tu servidor antes de publicar estos tipos. Las previsualizaciones móviles siguen funcionando con clientes anteriores.

Compila para los sistemas operativos y las arquitecturas de CPU de tus destinatarios. Tuist no realiza compilación cruzada de tu app ni instala sus dependencias; las herramientas para Linux también necesitan bibliotecas del sistema compatibles.

Las previsualizaciones se ejecutan con los permisos de tu cuenta de usuario, no en un entorno aislado. Ejecuta solo compilaciones procedentes de autores y pull requests en los que confíes.

Consulta <.localized_link href="/guides/features/previews/run/cli">Ejecutar previsualizaciones con la CLI</.localized_link> para conocer el comportamiento de ejecución y el reenvío de argumentos, y la <.localized_link href="/guides/features/previews#visibility">visión general de las previsualizaciones</.localized_link> para información sobre acceso, pistas e insignias para el README.
