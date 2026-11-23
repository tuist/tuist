---
{
  "title": "Caché de Bazel",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Comparte entradas de la caché remota de Bazel con tu equipo y CI mediante Tuist."
}
---
# Caché de Bazel {#bazel-cache}

Tuist expone una caché de la [API de ejecución remota](https://github.com/bazelbuild/remote-apis) a la que Bazel se conecta como caché remota. Cuando los resultados de una acción ya están en la caché, Bazel omite la acción y obtiene el resultado de la caché de Tuist, ahorrando tiempo de compilación para todo tu equipo y en entornos de CI. Para configurar GitHub Actions, consulta [Bazel en GitHub Actions](https://tuist.dev/solutions/bazel-github-actions). Para saber cómo funciona la caché remota y comparar las cachés autoalojadas con las gestionadas, consulta [Caché remota de Bazel](https://tuist.dev/solutions/bazel-remote-cache).

## Configuración {#setup}

Desde la raíz del espacio de trabajo de Bazel, ejecuta:

```bash
tuist bazel setup
```

Esto crea un archivo `.bazelrc.tuist` junto a tu `.bazelrc`, configurado para la región de caché de Tuist más cercana y autenticado mediante un asistente de credenciales por espacio de trabajo. También añade una línea `try-import` al `.bazelrc` de tu repositorio:

```text
try-import %workspace%/.bazelrc.tuist
```

Pasa `--no-add-bazelrc-import` si quieres gestionar la importación tú mismo.

Añade `.bazelrc.tuist` a tu `.gitignore` y ejecuta la configuración en cada máquina en lugar de confirmar el archivo. El archivo generado apunta a una ruta absoluta del asistente de credenciales dentro del directorio de configuración de Tuist del usuario actual y a la región de caché más cercana a la máquina que lo generó, por lo que ninguno de esos valores es válido para un compañero de equipo o un ejecutor de integración continua. Confirma la línea `try-import` en `.bazelrc`, que es igual en todas las máquinas.

La configuración no modifica un `.bazelrc` existente cuando no encuentra un marcador de espacio de trabajo de Bazel, cuando el archivo es un enlace simbólico o cuando ya configura una caché remota o el servicio de eventos de compilación. Así, volver a ejecutarla es idempotente.

Ejecuta un comando normal de Bazel para verificar la integración:

```bash
bazel build //...
```

La actividad de la caché aparece entonces en la página **Caché de Bazel** del proyecto en el panel de Tuist, que muestra la transferencia de caché, descargas y subidas, latencia de lectura y escritura, rendimiento y la tasa de aciertos de la caché de acciones. La **Vista general** del proyecto incluye un resumen de esa misma tasa de aciertos de la caché de acciones junto con la duración de la compilación.

Para ver cómo un comando utilizó la caché, ábrelo desde **Invocaciones**. La página de invocación separa las consultas a la caché de acciones de las solicitudes de objetos de contenido, de modo que puedes distinguir una caché de acciones fría de una descarga lenta de artefactos.

## Ejecución remota {#remote-execution}

Tuist también puede ejecutar tus acciones de Bazel en sus ejecutores Linux, de modo que los fallos de caché se ejecutan de forma remota en lugar de en la máquina local o en el ejecutor de CI. La ejecución remota está disponible para cuentas habilitadas; [envíanos un correo](mailto:contact@tuist.dev) o [reserva una llamada](https://cal.tuist.dev/team/tuist/tuist) para habilitarla en la tuya. Luego pasa `--remote-execution` a la configuración:

```bash
tuist bazel setup --remote-execution
```

La configuración apunta entonces a Bazel hacia el ejecutor de Tuist en `.bazelrc.tuist`, junto a la caché remota. Consulta el ejecutor y la imagen actuales cada vez que se ejecuta, así que vuelve a ejecutar la configuración en lugar de copiar los valores generados. Las acciones se ejecutan con la cadena de herramientas Linux del ejecutor, no con las herramientas instaladas en tu máquina, así que declara en el espacio de trabajo las cadenas de herramientas que necesiten tus acciones.

La configuración también establece `--jobs` al doble del número de acciones remotas que tu cuenta puede ejecutar a la vez, de modo que cada una tenga la siguiente acción en espera. Sin esto, Bazel ejecuta tantas acciones en paralelo como núcleos tenga la máquina, y un ejecutor de CI de 2 núcleos mantiene solo dos acciones remotas en vuelo.

Para usar otro valor, pasa `--jobs` en la línea de comandos o establécelo en `.bazelrc` después de la línea `try-import`. Bazel usa el último valor que lee, por lo que un `--jobs` anterior a esa línea se reemplaza por el generado.

### Tamaños de ejecutor {#executor-sizes}

Las acciones usan 4 GB de memoria y 2 vCPU de forma predeterminada. Establece la propiedad de ejecución `tuist-memory-gb` para solicitar una VM más pequeña o más grande:

| `tuist-memory-gb` | Memoria | vCPU | Disco del espacio de trabajo |
| --- | --- | --- | --- |
| `2` | 2 GB | 1 | 30 GB |
| `4` (predeterminado) | 4 GB | 2 | 30 GB |
| `8` | 8 GB | 4 | 30 GB |
| `16` | 16 GB | 8 | 30 GB |

Por ejemplo, añade esto **después** de la línea `try-import` en `.bazelrc` para solicitar 8 GB de forma predeterminada:

```text
build --remote_default_exec_properties=tuist-memory-gb=8
```

Para un objetivo concreto, usa `exec_properties = {"tuist-memory-gb": "8"}` en su regla de Bazel. Solo se admiten `2`, `4`, `8` y `16`. `2` ejecuta el doble de acciones a la vez dentro de los mismos límites, pero los pasos grandes de compilador y enlazador pueden quedarse sin memoria; vuelve a establecer esos objetivos a `4` o más. Las acciones más grandes consumen proporcionalmente más de los límites de vCPU y memoria asignados a la cuenta, reduciendo cuántas pueden ejecutarse simultáneamente. Una forma debe cumplir ambos límites. El `--jobs` generado usa la forma predeterminada; anúlalo si es necesario al solicitar formas más grandes.

Los ejecutores usan actualmente la imagen Linux amd64 de Tuist. Las imágenes de contenedor arbitrarias, otros sistemas operativos y arquitecturas de ejecución, workers persistentes de acciones y ejecutores propios no se configuran mediante la configuración. Vuelve a ejecutar la configuración para obtener la imagen y el endpoint actuales.

### Ejecución de acciones y uso {#running-actions-and-usage}

La página **Ejecución remota** del proyecto muestra qué se está ejecutando ahora y qué se ha ejecutado:

- **Invocaciones** lista primero las invocaciones de Bazel en ejecución, actualizadas cada cinco segundos, con el tiempo que lleva cada una y cuántas de sus acciones remotas están en ejecución y en cola. Una invocación aparece cuando Kura tiene sus patrones de objetivo y permanece hasta que llega su informe completado. Al abrir una se muestran sus **Ejecuciones**: primero sus acciones remotas que se están ejecutando en una VM o esperando una, luego las 50 que finalizaron más recientemente con su resultado (Aprobado, En caché, Fallido o Error), cada una con su mnemotécnico, objetivo, tamaño de máquina y duración hasta el momento. Una acción que acaba de finalizar se muestra como **Finalizando** durante hasta un minuto hasta que llegue su registro. Cada fila abre la página de la acción; mientras la acción sigue en ejecución, la página muestra su estado, máquina y digest, y carga el registro completo cuando finaliza. Las acciones que la puerta de enlace de ejecución ejecuta en una VM preparada de antemano no se listan mientras se ejecutan; aparecen entre las finalizadas. Las invocaciones en ejecución no se muestran mientras buscas o filtras la lista.
- **Análisis** comienza con **Ejecuciones** y **Tiempo total de ejecución** para el periodo seleccionado, con cambios respecto al periodo anterior y un gráfico temporal. El tiempo total de ejecución es el tiempo que el ejecutor de cada acción estuvo activo en su VM, incluida la obtención de entradas y la subida de salidas, pero sin contar la puesta en cola ni la preparación de la VM. Es el tiempo que factura la página de **Uso**. Los resultados servidos desde la caché no son ejecuciones.

Los mismos datos están disponibles en `GET /api/projects/{account_handle}/{project_handle}/remote-execution/activity` y `GET /api/projects/{account_handle}/{project_handle}/remote-execution/usage` (`from` y `to` opcionales, con valores predeterminados de los últimos 30 días y un máximo de 366), y en las herramientas MCP `get_remote_execution_activity` y `get_remote_execution_usage`.

### Tiempos de acciones remotas {#remote-action-timings}

El resto de **Análisis** y la tabla de **Invocaciones** cubren acciones con fases remotas registradas: tiempos medios y p50/p90/p99 de cola y ejecución, con cambios respecto al periodo anterior, gráficos de tendencia y enlaces a los tiempos por fase de cada invocación. Filtra por fecha (hasta 90 días). La tabla de invocaciones muestra el tiempo medio, p50 y p90 de ejecución de cada invocación. Búscala por comando, objetivo o ID de invocación, filtra por estado, comando, objetivos o número de acciones remotas y ordena por cualquier columna excepto Invocación. La búsqueda y los filtros de la tabla se aplican solo a la tabla de invocaciones, no a los análisis.

Abre la pestaña **Ejecución remota** de una invocación para ver sus **Ejecuciones**, es decir, sus acciones remotas ordenadas por duración (de mayor a menor) o por hora de inicio: una fila por acción remota con su momento de inicio respecto al perfil, su duración y una barra dividida en tiempos de cola, obtención de entradas, ejecución y subida de salidas, escalada a la acción más larga de la página. Pasa el cursor sobre una barra para ver la duración de cada fase. La tabla utiliza perfiles de Bazel subidos y asocia las fases del servidor únicamente con una acción inequívoca en el mismo hilo del perfil.

La ausencia de tiempos significa **No registrado**, no cero. Los perfiles antiguos, los intervalos de acción faltantes y las fases cortas omitidas por Bazel pueden dejar la tabla vacía aunque haya habido trabajo remoto. Los reintentos registrados se suman dentro de cada acción. Los metadatos del servidor pueden describir un resultado servido desde la caché, por lo que estos tiempos no son prueba de una ejecución nueva ni de uso facturable. Las subidas de entradas del cliente y las subidas de salidas ejecutadas localmente se excluyen del tiempo de subida de salidas.

Los mismos datos están disponibles en el endpoint REST de pasos de compilación con `remote_execution=true` y en las herramientas MCP `list_bazel_build_steps` / `get_bazel_build_step`. Los tiempos se conservan durante 90 días junto con los pasos del perfil.

### Inspeccionar una acción remota {#inspect-a-remote-action}

Cuando el ejecutor de Tuist registra una acción, su fila en la pestaña **Ejecución remota** de la invocación enlaza a la página de la acción. **Resumen** muestra el estado y el código de salida, los tiempos de cola, obtención de entradas, ejecución y subida de salidas, si la acción se programó o se ejecutó en un worker alquilado para la invocación, el worker, la memoria, el tiempo de espera y el digest de la acción. Una acción fallida también recibe una tarjeta de **Errores**: errores del compilador reconocidos en su error estándar (formatos de Clang, GCC, Swift, javac, Go y rustc) agrupados por archivo, o su código de salida y el final de su error estándar cuando no se reconoce ninguno. **Registros** muestra la salida estándar seguida del error estándar en un único registro con números de línea, resaltando las líneas de error. Al igual que un registro de trabajo de CI, se abre al final y **Cargar líneas anteriores** permite retroceder páginas. Un registro conserva los primeros 16 KiB de cada flujo; el ejecutor también almacena un flujo más largo completo como artefacto de ejecución, por lo que el registro y la tarjeta de **Errores** cubren toda la salida. Un flujo superior a 16 MiB conserva solo sus primeros 16 KiB y sus últimos 16 MiB. Un marcador en el registro indica dónde faltan bytes y por qué: omitidos de un flujo muy largo o no almacenados, por ejemplo, una vez que la copia ha caducado. La tarjeta **Comando** en **Resumen** muestra la línea de comandos, que **Copiar** copia, el directorio de trabajo y las rutas de salida, y las propiedades de entorno y plataforma en secciones contraídas.

Las variables de entorno cuyos nombres contienen `TOKEN`, `SECRET`, `PASSWORD` o `KEY`, y los valores de flags con esos nombres, se muestran como `****`. Los registros son de mejor esfuerzo: una fila sin enlace significa que ningún registro coincidió inequívocamente con su salida, no que la acción se ejecutara localmente. Los registros se conservan durante 90 días. Los endpoints REST `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations/{invocation_id}/remote-actions` y `.../remote-actions/{operation_id}` y las herramientas MCP `list_bazel_remote_actions` / `get_bazel_remote_action` devuelven los mismos registros; `.../remote-actions/{operation_id}/logs/{stdout|stderr}` y `get_bazel_remote_action_log` leen los registros por rango de bytes. Las copias de registros almacenadas son artefactos de ejecución y caducan con la ventana de artefactos de ejecución del plan.

## Análisis de compilaciones {#build-insights}

De forma predeterminada, `tuist bazel setup` también configura el Build Event Service de Bazel para que los comandos completados aparezcan en el panel de **Invocaciones**. Consulta <.localized_link href="/guides/features/build-insights/bazel">Análisis de compilaciones de Bazel</.localized_link> para saber qué muestra el panel y cómo adjuntar metadatos personalizados.

Si solo quieres la caché remota y prefieres no enviar el flujo de eventos de compilación, opta por no incluirlo con:

```bash
tuist bazel setup --no-build-insights
```

## Integración continua {#continuous-integration}

Autentica la CI con uno de los métodos de la <.localized_link href="/guides/server/authentication#continuous-integration">Guía de autenticación</.localized_link> y luego ejecuta `tuist bazel setup` una vez como parte del paso de checkout para que `.bazelrc.tuist` refleje la región correcta para el runner. Consulta la <.localized_link href="/guides/integrations/continuous-integration">Guía de integración continua</.localized_link> para ver ejemplos específicos de cada proveedor.

## Retención de datos {#data-retention}

Tuist conserva las observaciones de la caché remota durante 90 días. Consulta <.localized_link href="/guides/server/data-retention">retención de datos</.localized_link> para ver la política completa.
