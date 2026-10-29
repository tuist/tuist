---
{
  "title": "Bazel cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Bazel remote cache entries across your team and CI with Tuist."
}
---
# Caché de Bazel {#bazel-cache}

Tuist expone una caché de [Remote Execution API](https://github.com/bazelbuild/remote-apis) a la que Bazel se conecta como caché remota. Cuando los resultados de una acción ya están en la caché, Bazel omite la acción y obtiene el resultado desde la caché de Tuist, ahorrando tiempo de compilación para tu equipo y en entornos de CI.

## Configuración {#setup}

Desde la raíz del espacio de trabajo de Bazel, ejecuta:

```bash
tuist bazel setup
```

Esto escribe un archivo `.bazelrc.tuist` junto a tu `.bazelrc`, configurado para la región de caché de Tuist más cercana y autenticado mediante un asistente de credenciales por espacio de trabajo. También añade una línea `try-import` al archivo `.bazelrc` de tu repositorio:

```text
try-import %workspace%/.bazelrc.tuist
```

Pasa `--no-add-bazelrc-import` si deseas gestionar la importación tú mismo.

Añade `.bazelrc.tuist` a tu `.gitignore` y ejecuta la configuración en cada máquina en lugar de confirmar el archivo. El archivo generado apunta a una ruta absoluta del asistente de credenciales dentro del directorio de configuración de Tuist del usuario actual y a la región de caché más cercana a la máquina que lo generó, por lo que ninguno de estos valores se transfiere a un compañero de equipo o a un ejecutor de integración continua. Confirma la línea `try-import` en `.bazelrc`, que es la misma en todas las máquinas.

La configuración deja intacto un `.bazelrc` existente cuando no puede encontrar un marcador de espacio de trabajo de Bazel, cuando el archivo es un enlace simbólico o cuando ya configura una caché remota o Build Event Service. De esta forma, volver a ejecutarla es idempotente.

Ejecuta un comando normal de Bazel para verificar la integración:

```bash
bazel build //...
```

La actividad de la caché aparece entonces en la página **Bazel Cache** del proyecto en el panel de Tuist, que muestra la transferencia de caché, descargas y subidas, latencia de lectura y escritura, rendimiento y la tasa de aciertos de la caché de acciones. La **Vista general** del proyecto incluye un resumen de la misma tasa de aciertos de la caché de acciones junto con la duración de la compilación.

Para ver cómo un comando utilizó la caché, ábrelo desde **Invocaciones**. La página de invocaciones separa las búsquedas en la caché de acciones de las solicitudes de objetos de contenido, de modo que puedes distinguir una caché de acciones fría de una descarga lenta de artefactos.

## Información de compilación {#build-insights}

De forma predeterminada, `tuist bazel setup` también configura Build Event Service de Bazel para que los comandos completados aparezcan en el panel de **Invocaciones**. Consulta <.localized_link href="/guides/features/build-insights/bazel">Información de compilación de Bazel</.localized_link> para saber qué muestra el panel y cómo adjuntar metadatos personalizados.

Si solo deseas la caché remota y prefieres no enviar el flujo de eventos de compilación, opta por no incluirlo con:

```bash
tuist bazel setup --no-build-insights
```

## Integración continua {#continuous-integration}

Autentica la CI con uno de los métodos de la <.localized_link href="/guides/server/authentication#continuous-integration">Guía de autenticación</.localized_link>, luego ejecuta `tuist bazel setup` una vez como parte del paso de checkout para que `.bazelrc.tuist` refleje la región correcta para el ejecutor. Consulta la <.localized_link href="/guides/integrations/continuous-integration">Guía de integración continua</.localized_link> para ver ejemplos específicos de cada proveedor.

## Retención de datos {#data-retention}

Tuist conserva las observaciones de la caché remota durante 90 días. Consulta <.localized_link href="/guides/server/data-retention">retención de datos</.localized_link> para conocer la política completa.
