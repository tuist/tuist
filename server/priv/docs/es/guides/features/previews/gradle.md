---
{
  "title": "Previews de Gradle",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Compila y comparte aplicaciones Android y herramientas nativas de línea de comandos desde proyectos de Gradle con las Previews de Tuist."
}
---
# Vistas previas de Gradle

Compila y comparte aplicaciones Android y herramientas nativas de línea de comandos directamente desde Gradle. Comienza con la <.localized_link href="/guides/get-started/gradle-project">guía del proyecto Gradle</.localized_link> para conectar el proyecto y autenticarte.

## Aplicaciones Android

```bash
./gradlew :app:tuistShareDebug
```

El plugin de configuración `dev.tuist` registra una tarea `tuistShare<Variant>` para cada variante de aplicación del Android Gradle Plugin (8.8.2 o posterior). Sustituye `app` y `Debug` por tu módulo de aplicación y variante, por ejemplo `:app:tuistShareDemoDebug` para un flavor de producto. La tarea compila el APK a través de las dependencias de artefactos declaradas en Gradle antes de publicarlo. También funciona cuando los resultados de compilación están actualizados o se restauran desde la caché de compilación.

Solo se admite un único APK de aplicación universal firmado. La variante de depuración de Android suele usar una clave de firma de depuración; las variantes de release necesitan tu propia configuración de firma. La tarea verifica la firma del APK antes de la autenticación o la subida. Se rechazan los APK sin firmar, no válidos, de instrumentación y divididos. Los módulos de biblioteca, los APK de test y los Android App Bundles (`.aab`) no son objetivos de publicación.

## Herramientas nativas de línea de comandos

Los proyectos que usan el plugin `cpp-application` o `swift-application` de Gradle obtienen una tarea de compartir para cada binario nativo:

```bash
./gradlew :app:tuistShareMainDebug
```

La tarea compila y empaqueta la distribución instalada, incluido su lanzador y las bibliotecas en tiempo de ejecución. Usa `tuistShareMainRelease` para el binario de release. Los proyectos dirigidos a varias máquinas tienen una tarea para cada binario; ejecuta `./gradlew :app:tasks --all` para encontrar sus nombres.

Se admiten ejecutables nativos de macOS y Linux para arm64 o x86_64. Compila en la plataforma objetivo con la toolchain requerida por tu plugin de Gradle. Las aplicaciones JVM y sus scripts de lanzador generados no son compatibles con esta integración.

## Comportamiento de publicación

Las tareas de compartir publican usando las credenciales de Tuist existentes del plugin, sin invocar la CLI de Tuist. Las tareas ordinarias `assemble`, `build` y de test nunca publican vistas previas.

Después de compartir, abre **Vistas previas** en tu proyecto para copiar el enlace. Repetir una compartición de la misma compilación y track reutiliza su publicación, incluso después de un acierto de caché de compilación. Las subidas fallidas o no confirmadas hacen que falle la tarea de compartir; no se informan como vistas previas exitosas.

## CI y tracks

Configura la <.localized_link href="/guides/integrations/continuous-integration">autenticación de CI</.localized_link> con las mismas credenciales que usas para otras funcionalidades autenticadas del plugin y luego solicita la publicación explícitamente:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

Añade `--track nightly` a una tarea de compartir nativa de la misma manera. Las tareas usan el proyecto de Tuist configurado, la URL del servidor y la configuración de proxy. La publicación de vistas previas siempre requiere autenticación. Los metadatos de revisión de Git, las notas de release y los comentarios automáticos de pull request no son adjuntados por estas tareas.

Las publicaciones de artefactos caducan después de 30 días en Tuist alojado. Las instancias autoalojadas usan `TUIST_APP_PREVIEW_RETENTION_DAYS`; dejarlo sin configurar desactiva la caducidad para esta familia. Las publicaciones caducadas no pueden reactivarse repitiendo la misma intención.

## Compartir un APK existente

Para un APK compilado fuera de este flujo de trabajo, o para incluir notas de release con el flujo de subida heredado, la CLI sigue estando disponible:

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

Consulta <.localized_link href="/guides/features/previews#run-a-preview">Ejecutar una vista previa</.localized_link> para ejecutar compilaciones publicadas, acceso, tracks y badges de README.

<!-- @snippet: ./_tuist-share -->
