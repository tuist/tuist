---
{
  "title": "Análisis de compilaciones de Bazel",
  "titleTemplate": ":title · Análisis de compilaciones · Funcionalidades · Guías · Tuist",
  "description": "Haz seguimiento de la duración de los comandos de Bazel, totales de caché y diagnósticos de ruta crítica en el panel de control de Tuist."
}
---
# Análisis de compilaciones de Bazel {#bazel-build-insights}

Cada comando de Bazel completado, como `build`, `test` y otros, aparece en el panel \*\***Invocaciones**\*\* del proyecto: tipo de comando, estado de salida, hora de inicio y finalización, duración, así como los aciertos y fallos de caché, las descargas y las subidas que Bazel atribuyó a esa misma invocación.

Los datos de invocación se entregan a través del [Build Event Protocol](https://bazel.build/remote/bep) de Bazel. La configuración lo integra automáticamente cuando ejecutas `tuist bazel setup`; no se requieren flags adicionales para empezar a ver las invocaciones.

## Qué muestra el panel {#what-the-dashboard-shows}

Cada invocación registra:

- El comando que ejecutó Bazel, su código de salida, la hora de inicio y finalización, y la duración total.
- Recuentos de acciones, targets y paquetes.
- Una línea de tiempo de compilación acotada y un resumen de la ruta crítica.
- Aciertos y fallos de caché, descargas y subidas atribuidos a la invocación.
- Líneas del registro de progreso capturadas durante la ejecución, en orden de ejecución.
- La versión de Bazel, la rama y el commit de git cuando Bazel los reporta, y si la ejecución se realizó en CI.

La actividad de caché que Bazel no puede atribuir a una invocación completada, por ejemplo cuando un comando se interrumpe a mitad de ejecución, sigue apareciendo en la **Vista general** del proyecto como una observación bruta de la caché remota. No se trata como evidencia del éxito del comando, su duración o los resultados de los tests.

## Metadatos personalizados {#custom-metadata}

Asocia datos clave-valor a las invocaciones para comparar ejecuciones de diferentes equipos, hardware o flujos de trabajo. Los valores aparecen en la página de detalles de cada invocación y a través de la interfaz de programación de aplicaciones y las herramientas del Model Context Protocol.

Establece metadatos con el flag integrado de Bazel `--build_metadata`:

```bash
bazel build --build_metadata=TICKET=TUIST-123 --build_metadata=RUNNER=macos-14 //...
```

O establécelos una vez por lane en tu `.bazelrc`:

```text
build:ci --build_metadata=RUNNER=macos-14
```

Cada invocación puede llevar hasta 20 entradas personalizadas. Las claves pueden contener hasta 50 caracteres y los valores hasta 500 caracteres. Las entradas que superen esos límites se descartan antes de almacenar la invocación, por lo que una entrada no válida no impide que el resto del informe se registre.

Las claves de contexto que Tuist deriva del entorno de compilación, como `CI`, `GIT_BRANCH` y `GIT_COMMIT`, no se almacenan como valores personalizados porque ya rellenan campos principales en la invocación.

Los metadatos personalizados son visibles para los miembros del proyecto en el panel y a través de la interfaz de programación de aplicaciones y las herramientas del Model Context Protocol. No los uses para credenciales, tokens de acceso u otros datos sensibles.

## Optar por no participar {#opting-out}

El flujo del Build Event Protocol transporta argumentos de línea de comandos, valores del entorno y la salida del comando. Tuist solo conserva los campos de comandos completados enumerados anteriormente y descarta el resto, pero si prefieres no enviar el flujo de eventos en absoluto, vuelve a ejecutar la configuración con:

```bash
tuist bazel setup --no-build-insights
```

El `.bazelrc.tuist` generado configura entonces solo la caché remota. Las invocaciones dejan de aparecer en el panel y las observaciones de caché permanecen en la página de **Vista general**.

## Retención de datos {#data-retention}

Tuist conserva las invocaciones de Bazel y sus registros durante 90 días. Consulta <.localized_link href="/guides/server/data-retention">la retención de datos</.localized_link> para conocer la política completa.
