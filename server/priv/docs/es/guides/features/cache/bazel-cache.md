---
{
  "title": "Caché de Bazel",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Comparte entradas de la caché remota de Bazel con tu equipo y CI mediante Tuist."
}
---
# Caché de Bazel {#bazel-cache}

Tuist expone una caché de la [API de ejecución remota](https://github.com/bazelbuild/remote-apis) a la que Bazel se conecta como caché remota. Cuando las salidas de una acción ya están en la caché, Bazel omite la acción y obtiene el resultado de la caché de Tuist, ahorrando tiempo de compilación para todo tu equipo y en los entornos de CI. Para configurar GitHub Actions, consulta [Bazel en GitHub Actions](https://tuist.dev/solutions/bazel-github-actions). Para saber cómo funciona la caché remota y comparar las cachés autoalojadas con las gestionadas, consulta [Caché remota de Bazel](https://tuist.dev/solutions/bazel-remote-cache).

## Configuración {#setup}

Desde la raíz del espacio de trabajo de Bazel, ejecuta:

```bash
tuist bazel setup
```

Esto crea un archivo `.bazelrc.tuist` junto a tu `.bazelrc`, configurado para la región de caché de Tuist más cercana y autenticado mediante un asistente de credenciales por espacio de trabajo. También añade una línea `try-import` al `.bazelrc` de tu repositorio:

```text
try-import %workspace%/.bazelrc.tuist
```

Pasa `--no-add-bazelrc-import` si quieres gestionar tú mismo la importación.

Añade `.bazelrc.tuist` a tu `.gitignore` y ejecuta la configuración en cada máquina en lugar de confirmarlo en el control de versiones. El archivo generado apunta a una ruta absoluta del asistente de credenciales dentro del directorio de configuración de Tuist del usuario actual y a la región de caché más cercana a la máquina que lo generó, por lo que ninguno de esos valores sirve para un compañero de equipo o para un ejecutor de integración continua. Confirma la línea `try-import` en `.bazelrc`, que es la misma en todas las máquinas.

La configuración no modifica un `.bazelrc` existente cuando no puede encontrar un marcador de espacio de trabajo de Bazel, cuando el archivo es un enlace simbólico o cuando ya configura una caché remota o el servicio de eventos de compilación. De este modo, volver a ejecutarla es idempotente.

Ejecuta un comando normal de Bazel para verificar la integración:

```bash
bazel build //...
```

La actividad de la caché aparece entonces en la página **Caché de Bazel** del proyecto en el panel de Tuist, que muestra la transferencia de caché, descargas y subidas, latencia de lectura y escritura, rendimiento y la tasa de aciertos de la caché de acciones. La **Vista general** del proyecto incluye un resumen de esa misma tasa de aciertos de la caché de acciones junto con la duración de la compilación.

Para ver cómo un comando utilizó la caché, ábrelo desde **Invocaciones**. La página de invocación separa las búsquedas en la caché de acciones de las solicitudes de objetos de contenido, de modo que puedes distinguir una caché de acciones fría de una descarga lenta de artefactos.

## Ejecución remota {#remote-execution}

Tuist también puede ejecutar tus acciones de Bazel en sus ejecutores Linux, de modo que los fallos de caché se ejecutan de forma remota en lugar de en la máquina local o en el ejecutor de CI. La ejecución remota está disponible para cuentas habilitadas; [escríbenos](mailto:contact@tuist.dev) o [reserva una llamada](https://cal.tuist.dev/team/tuist/tuist) para activarla en la tuya. Luego pasa `--remote-execution` a la configuración:

```bash
tuist bazel setup --remote-execution
```

La configuración apunta entonces a Bazel hacia el ejecutor de Tuist en `.bazelrc.tuist`, junto a la caché remota. Consulta el ejecutor y la imagen actuales cada vez que se ejecuta, así que vuelve a ejecutar la configuración en lugar de copiar los valores generados. Las acciones se ejecutan con la cadena de herramientas Linux del ejecutor, no con las herramientas instaladas en tu máquina, por lo que debes declarar las cadenas de herramientas que necesitan tus acciones en el espacio de trabajo.

La configuración también establece `--jobs` al doble del número de acciones remotas que tu cuenta puede ejecutar a la vez, de modo que cada una tenga la siguiente acción en espera. Sin esto, Bazel ejecuta tantas acciones en paralelo como núcleos tenga la máquina, y un ejecutor de CI de 2 núcleos mantiene solo dos acciones remotas en vuelo.

Para usar un valor diferente, pasa `--jobs` en la línea de comandos o establécelo en `.bazelrc` después de la línea `try-import`. Bazel usa el último valor que lee, por lo que un `--jobs` anterior a esa línea se reemplaza por el generado.

### Tamaños de ejecutor {#executor-sizes}

Las acciones usan 4 GB de memoria y 2 vCPU de forma predeterminada. Establece la propiedad de ejecución `tuist-memory-gb` para solicitar una VM más grande:

| `tuist-memory-gb` | Memoria | vCPU | Disco del espacio de trabajo |
| --- | --- | --- | --- |
| `4` (predeterminado) | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

Por ejemplo, añade esto **después** de la línea `try-import` en `.bazelrc` para solicitar 8 GB de forma predeterminada:

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

Para un único objetivo, usa `exec_properties = {"tuist-memory-gb": "8"}` en su regla de Bazel. Solo se admiten `4`, `8` y `16`. Las acciones más grandes consumen proporcionalmente más de los límites de vCPU y memoria asignados a la cuenta, lo que reduce cuántas pueden ejecutarse simultáneamente. Una forma debe cumplir ambos límites. El `--jobs` generado usa la forma predeterminada; anúlalo si es necesario al solicitar formas más grandes.

Los ejecutores usan actualmente la imagen Linux amd64 de Tuist. Las imágenes de contenedor arbitrarias, otros sistemas operativos y arquitecturas de ejecución, workers de acción persistentes y ejecutores propios no se configuran mediante la configuración. Vuelve a ejecutar la configuración para obtener la imagen y el extremo actuales.

### Acciones en ejecución y uso {#running-actions-and-usage}

La página **Ejecución remota** del proyecto muestra qué se está ejecutando ahora y qué se ha ejecutado:

- **Invocaciones** lista primero las invocaciones de Bazel en ejecución, actualizadas cada cinco segundos, con el tiempo que lleva cada una y cuántas de sus acciones remotas se están ejecutando y están en cola. Una invocación aparece una vez que Kura tiene sus patrones de objetivo y permanece hasta que llega su informe completado. Al abrir una se muestran sus **Ejecuciones**: sus acciones remotas que se están ejecutando en una VM o esperando una, con el mnemónico, el objetivo, el tamaño de la máquina y el tiempo en su estado actual de cada acción. Las acciones que la puerta de enlace de ejecución ejecuta en una VM preparada de antemano no aparecen mientras se ejecutan; sus tiempos aparecen una vez finalizada la invocación. Las invocaciones en ejecución no se muestran mientras buscas o filtras la lista.
- **Análisis** comienza con **Ejecuciones** y **Tiempo total de ejecución** para el periodo seleccionado, con cambios respecto al periodo anterior, graficados por tamaño de máquina. El tiempo total de ejecución es el tiempo que el ejecutor de cada acción estuvo activo en su VM, incluida la obtención de entradas y la subida de salidas, pero sin contar la puesta en cola ni la preparación de la VM. Es el tiempo que factura la página **Uso**. Los resultados servidos desde la caché no son ejecuciones.

Los mismos datos están disponibles en `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` y `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage` (`from` y `to` opcionales, con valores predeterminados de los últimos 30 días y un máximo de 366), y en las herramientas MCP `get_remote_execution_activity` y `get_remote_execution_usage`.

### Tiempos de acciones remotas {#remote-action-timings}

El resto de **Análisis** y la tabla de **Invocaciones** cubren acciones con fases remotas registradas: tiempos promedio y p50/p90/p99 de cola y ejecución, con cambios respecto al periodo anterior, gráficos de tendencias y enlaces a los tiempos por fase de cada invocación. Filtra por fecha (hasta 90 días). La tabla de invocaciones muestra el tiempo de ejecución promedio, p50 y p90 de cada invocación. Búscala por comando, objetivo o ID de invocación, filtra por estado, comando, objetivos o número de acciones remotas y ordena por cualquier columna excepto Invocación. Los filtros de búsqueda y de tabla se aplican solo a la tabla de invocaciones, no a los análisis.

Abre la pestaña **Ejecución remota** de una invocación para ver sus **Ejecuciones**, sus acciones remotas ordenadas por duración (de mayor a menor) o por hora de inicio: una fila por acción remota con el momento en que comenzó respecto al perfil, su duración y una barra dividida en tiempos de cola, obtención de entradas, ejecución y subida de salidas, escalada a la acción más larga de la página. Pasa el cursor sobre una barra para ver la duración de cada fase. La tabla utiliza perfiles de Bazel subidos y asocia las fases del servidor únicamente con una acción inequívoca en el mismo hilo del perfil.

Los tiempos faltantes significan **No registrado**, no cero. Perfiles antiguos, intervalos de acción faltantes y fases cortas omitidas por Bazel pueden dejar la tabla vacía incluso cuando hubo trabajo remoto. Las reintentos registrados se suman dentro de cada acción. Los metadatos del servidor pueden describir un resultado almacenado en caché, por lo que estos tiempos no son prueba de una ejecución nueva ni de uso facturable. Las subidas de entradas del cliente y las subidas de salidas ejecutadas localmente se excluyen del tiempo de subida de salidas.

Los mismos datos están disponibles desde el extremo REST de pasos de compilación con `remote_execution=true` y las herramientas MCP `list_bazel_build_steps` / `get_bazel_build_step`. Los tiempos se conservan durante 90 días junto con los pasos del perfil.

## Análisis de compilaciones {#build-insights}

De forma predeterminada, `tuist bazel setup` también configura el Build Event Service de Bazel para que los comandos completados aparezcan en el panel de **Invocaciones**. Consulta <.localized_link href="/guides/features/build-insights/bazel">Análisis de compilaciones de Bazel</.localized_link> para ver qué muestra el panel y cómo adjuntar metadatos personalizados.

Si solo quieres la caché remota y prefieres no enviar el flujo de eventos de compilación, opta por no incluirlo con:

```bash
tuist bazel setup --no-build-insights
```

## Integración continua {#continuous-integration}

Autentica la CI con uno de los métodos de la <.localized_link href="/guides/server/authentication#continuous-integration">Guía de autenticación</.localized_link> y luego ejecuta `tuist bazel setup` una vez como parte del paso de checkout para que `.bazelrc.tuist` refleje la región correcta para el runner. Consulta la <.localized_link href="/guides/integrations/continuous-integration">Guía de integración continua</.localized_link> para ver ejemplos específicos por proveedor.

## Retención de datos {#data-retention}

Tuist conserva las observaciones de la caché remota durante 90 días. Consulta <.localized_link href="/guides/server/data-retention">retención de datos</.localized_link> para ver la política completa.
