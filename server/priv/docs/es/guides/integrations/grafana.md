---
{
  "title": "Grafana",
  "titleTemplate": ":title | Integraciones | Guías | Tuist",
  "description": "Monitoriza la salud de las compilaciones, las duraciones y el ahorro de caché de Tuist en Grafana, y configura alertas para tu equipo."
}
---

# Integración con Grafana {#grafana}

La fuente de datos de Tuist te permite usar métricas de compilación, pruebas y caché en Grafana, incluidas las duraciones, los recuentos de fallos y el tiempo ahorrado informado gracias a la caché. Crea paneles centrados en los proyectos y las métricas que importan a tu equipo, o combina las métricas de Tuist con otras fuentes de datos en los paneles existentes de tu empresa. Usa las reglas de alerta y los canales de notificación de Grafana para avisar a tu equipo cuando las compilaciones se vuelvan más lentas o aumenten los fallos.

## Métricas disponibles {#metric-definitions}

Las tablas enumeran etiquetas legibles y sus identificadores de consulta. Las consultas de salud de compilación usan el identificador del campo `metric`; las consultas de duración de compilación y prueba seleccionan `average`, `p50`, `p90` o `p99` en el campo `series` .

### Recuentos de compilación y fiabilidad

| Métrica | Identificador | Qué mide |
| --- | --- | --- |
| Recuento de compilaciones | `builds` | Número de compilaciones registradas. |
| Compilaciones exitosas | `successful_builds` | Compilaciones que se completaron correctamente. |
| Compilaciones fallidas | `failed_builds` | Compilaciones que fallaron. |
| Compilaciones canceladas | `cancelled_builds` | Compilaciones registradas como canceladas. Consulta [diferencias entre sistemas de compilación](#build-systems) . |
| Tasa de éxito de compilación | `success_rate` | Exitosas ÷ (exitosas + fallidas), como porcentaje. |
| Compilaciones fallidas o lentas | `builds_needing_attention` | Compilaciones fallidas o lentas, contadas una vez por compilación. |

### Duraciones de compilación y prueba

| Métrica | Identificador | Qué mide |
| --- | --- | --- |
| Duración media | `average` | Duración promedio de las ejecuciones seleccionadas. |
| Duración mediana | `p50` | Percentil 50 de las duraciones de ejecución. |
| Duración del percentil 90 | `p90` | Duración por debajo de la cual se encuentra el 90 % de las ejecuciones. |
| Duración del percentil 99 | `p99` | Duración por debajo de la cual se encuentra el 99 % de las ejecuciones. |
| Umbral de compilación lenta | `slow_build_threshold` | Duración del percentil 90, o tu límite fijo en milisegundos. |

Las métricas de duración de prueba usan las ejecuciones de prueba registradas en Tuist. El umbral de compilación lenta solo se aplica a las compilaciones: una compilación es lenta cuando su duración supera ese umbral. Las compilaciones canceladas se cuentan por separado y se excluyen de la tasa de éxito de compilación.

### Ahorro de caché

| Métrica | Identificador | Qué mide |
| --- | --- | --- |
| Tiempo acumulado de tareas ahorrado (Gradle) | `cache_work_avoided` | Suma del tiempo estimado de ejecución de tareas evitado por aciertos de caché. |
| Compilaciones que reportan tiempo acumulado de tareas | `cache_work_avoided_samples` | Compilaciones con una estimación completa. |
| Tiempo de caché ahorrado reportado | `cache_time_saved` | Suma del ahorro de tiempo transcurrido reportado. |
| Compilaciones que reportan tiempo de caché ahorrado | `cache_time_saved_samples` | Compilaciones con un valor de ahorro válido. |

El plugin de Gradle reporta automáticamente el trabajo estimado evitado para los aciertos de caché de tareas locales y remotas. Para cada tarea en caché, resta la duración de restauración de la tarea del tiempo de ejecución original almacenado por Gradle, con un mínimo de cero. La estimación de compilación suma estos valores. Las tareas paralelas pueden superponerse, por lo que se trata de tiempo acumulado de tareas, no de tiempo de compilación transcurrido ahorrado. Las tareas actualizadas y omitidas están excluidas.

Una compilación sin aciertos de caché de tareas reporta cero. Si alguna tarea en caché carece de su temporización original, la telemetría está incompleta o el mapa de metadatos personalizados no tiene espacio, el plugin omite la estimación. Las versiones anteriores del plugin y otros sistemas de compilación no lo reportan. Compara el recuento de reportes con el total de compilaciones para verificar la cobertura.

El ahorro de tiempo transcurrido reportado proviene de los metadatos `tuist.cache_time_saved_ms`. Esta métrica permanece separada de la estimación automática.

El ahorro de caché no tiene valor cuando ninguna compilación lo reporta. Once no registra actualmente esta medición. Las tasas de aciertos y fallos de caché no están disponibles a través de esta fuente de datos.

### Tablas

Estos identificadores son valores del campo `queryType` de la consulta.

| Tabla | Tipo de consulta | Contenido |
| --- | --- | --- |
| Salud por carga de trabajo | `buildWorkloads` | Recuento de compilaciones, tasa de éxito, duración mediana y del percentil 90. |
| Categorías de fallo | `buildFailureReasons` | Todos los fallos y recuentos por categoría de fallo. |
| Compilaciones fallidas recientes | `buildRecentFailures` | Últimos 100 fallos, con enlaces a Tuist. |

Los fallos recientes incluyen hora de inicio, duración, usuario, rama y tareas solicitadas. Las categorías de fallo son `verification`, `infrastructure_tooling` y `unknown`.

Los resúmenes de carga de trabajo y las listas de valores de rama/carga de trabajo devuelven hasta 1000 valores. Las consultas de variables de salud de compilación usan los últimos 90 días; las consultas de variables heredadas de Gradle mantienen su ventana de historial existente. Bazel muestra el usuario de compilación reportado por la herramienta. Otras integraciones muestran la cuenta asociada con la credencial de reporte. Las ejecuciones históricas de Bazel y Once, y las ejecuciones de Once reportadas con credenciales de proyecto, aparecen como Desconocido cuando no se registró ningún usuario.

Usa el filtro de Categoría de fallo en Ejecuciones de compilación para encontrar fallos coincidentes. La categoría aparece en los detalles de compilación, con una sugerencia informativa que explica su significado; la vista general predeterminada y las tablas de Ejecuciones de compilación mantienen sus columnas existentes. Las compilaciones exitosas, canceladas e inacabadas no tienen categoría de fallo. La tarjeta de Análisis de caché de Gradle y los detalles de compilación muestran el Tiempo acumulado de tareas ahorrado; la información emergente explica la estimación y el efecto de las tareas paralelas. El widget de caché compara el rango seleccionado con el período inmediatamente anterior de igual longitud usando los mismos filtros. Las comparaciones son neutrales: un total mayor puede reflejar más compilaciones. Las estimaciones anteriores faltantes no muestran comparación; una línea base cero registrada muestra el aumento absoluto en lugar de un porcentaje.

## Panel estándar {#what-you-can-query}

Importa [el panel de salud de compilación](https://github.com/tuist/tuist/blob/main/grafana-datasource/src/dashboards/build-health.json), luego selecciona tu fuente de datos y proyecto. Incluye recuento de compilaciones, tasa de éxito, duraciones mediana y del percentil 90, el umbral de compilación lenta, un recuento neutral de compilaciones fallidas o lentas, ahorro de caché agrupado y cobertura de reportes, y las tres tablas de fallos y carga de trabajo. Añade paneles para otras métricas disponibles según sea necesario. El umbral lento automático es el propio percentil 90 del período seleccionado; las compilaciones por encima de él no indican necesariamente una regresión. Establece un umbral fijo para las alertas de objetivo de duración. Los paneles de caché priorizan la estimación automática acumulada de tiempo de tarea de Gradle junto con su cobertura, seguida del ahorro de tiempo transcurrido reportado explícitamente junto con su propia cobertura.

## Sistemas de compilación {#build-systems}

Las consultas de salud de compilación y el panel estándar admiten Bazel, Once, Gradle y Xcode. Tuist selecciona el sistema de compilación desde tu proyecto. Los proyectos mixtos no son compatibles actualmente con las consultas de salud de compilación ni con el panel estándar.

| Sistema de compilación | Carga de trabajo | Reporte de cancelación | Ahorro de caché |
| --- | --- | --- | --- |
| Bazel | Comando | Código de salida 8, excepto `run` | Requiere metadatos personalizados |
| Once | Tipo de comando | Motivo de cancelación registrado | No registrado |
| Gradle | Grupo de tareas | Cancelaciones reportadas | Estimación automática de trabajo evitado; el ahorro de tiempo transcurrido requiere metadatos personalizados |
| Xcode | Esquema | No se distingue; el recuento es cero | Requiere metadatos personalizados |

Los registros en procesamiento y las ejecuciones no finalizadas se excluyen. Bazel incluye comandos de compilación, prueba, ejecución y cobertura. Once incluye ejecuciones de compilación, prueba y genéricas finalizadas.

Gradle agrupa las tareas como pruebas instrumentadas, pruebas unitarias, lint/verificaciones, ensamblado/paquete u Otros, en ese orden de precedencia. Cada compilación pertenece a una carga de trabajo. Los metadatos personalizados pueden anular las cargas de trabajo para Xcode, Bazel y Gradle.

### Categorías de fallo

| Categoría | Significado | Evidencia registrada |
| --- | --- | --- |
| `verification` | El código falló en la compilación, el enlazado, las pruebas o las verificaciones. | Excepciones de verificación o compilación de Gradle y tipos de tarea con fallo conocido; problemas del compilador y enlazador de Xcode; resultados estructurados no nulos de acciones de compilador/prueba de Bazel; fallos de prueba de Once o acciones fallidas declaradas explícitamente como compilación, enlazado, prueba, lint o verificación. |
| `infrastructure_tooling` | La compilación no pudo ejecutarse normalmente porque fallaron sus herramientas, dependencias o entorno. | Fallos de configuración, resolución de dependencias, entrada/salida o memoria de Gradle; fallos de infraestructura estructurados de Bazel y [códigos de salida documentados](https://bazel.build/run/scripts); errores de acción de infraestructura de Once. |
| `unknown` | El reporte no contiene suficiente evidencia para clasificar el fallo. | Comandos arbitrarios, diagnósticos faltantes y reportes antiguos sin evidencia estructurada. |

Los fallos en la fase de configuración de Gradle, incluidos los errores en los scripts de compilación, se agrupan bajo infraestructura/herramientas porque la ejecución de tareas no pudo continuar.

Los metadatos explícitos `tuist.failure_category` anulan la clasificación automática. De lo contrario, la evidencia de infraestructura tiene prioridad sobre la verificación cuando ambas ocurren en una compilación. Un script arbitrario fallido no se asume como un fallo del compilador o de prueba. Los reportes históricos pueden usar evidencia que Tuist ya almacena, pero los nuevos campos del reportero no rellenan información faltante. Los metadatos automáticos del reportero usan el espacio disponible dentro del límite existente de 20 entradas de metadatos personalizados.

La respuesta `buildFailureReasons` conserva su fila `all` por compatibilidad. El panel estándar filtra ese total fuera del gráfico de Categorías de fallo y muestra los fallos totales por separado. La consulta heredada `gradleFailureReasons` conserva sus tres filas de categoría originales.

## Opciones de consulta {#query-options}

Las consultas numéricas usan estos valores de `queryType`:

| Consulta | Tipo de consulta |
| --- | --- |
| Salud de compilación | `buildHealth` |
| Duraciones de compilación de Xcode | `buildDuration` |
| Duraciones de prueba | `testDuration` |

El campo `resultMode` controla cómo se devuelven los resultados:

| Resultado | Valor | Comportamiento |
| --- | --- | --- |
| Serie temporal | `series` | Un valor para cada intervalo. |
| Período completo | `total` | Un valor calculado a partir de todas las ejecuciones en el rango. |

Las etiquetas de filtro se asignan a estos campos de consulta:

| Filtro | Campo de consulta | Disponible en |
| --- | --- | --- |
| Entorno | `environment` | Todas las consultas |
| Rama | `gitBranch` | Consultas y tablas de salud de compilación |
| Carga de trabajo | `workload` | Consultas y tablas de salud de compilación |
| Estado | `status` | Consultas y tablas de salud de compilación, y duraciones de Xcode |
| Esquema | `scheme` | Duraciones de compilación y prueba de Xcode |
| Configuración | `configuration` | Duraciones de compilación de Xcode |
| Tipo de compilación | `category` | Duraciones de compilación de Xcode |

Los valores de entorno son `any`, `ci` (compilaciones automatizadas) y `local`. Los valores de estado son `success`, `failure` y, para consultas de salud de compilación, `cancelled`; omite el valor para incluir todos los estados. Los valores de tipo de compilación son `clean` e `incremental`; omite el valor para incluir ambos.

Los intervalos vacíos de salud de compilación tienen conteos cero y ningún valor de duración promedio, percentil de duración o tasa de éxito. El umbral de compilación lenta sigue usando el rango completo seleccionado. La consulta separada de duración de prueba devuelve cero para intervalos de serie temporal vacíos. Los percentiles de período completo se calculan a partir de ejecuciones, en lugar de percentiles de intervalo. Los percentiles de salud de compilación usan agregación exacta; las consultas separadas de duración de Xcode y prueba usan percentiles aproximados.

Las series temporales de salud de compilación colocan un primer bucket parcial al inicio del rango seleccionado para que siga siendo visible. Las consultas heredadas de Gradle conservan sus marcas de tiempo de bucket originales.

Todas las consultas aceptan rangos de fechas de hasta 366 días. Sus límites y marcas de tiempo difieren:

| Consulta | Marca de tiempo usada | Límites del rango |
| --- | --- | --- |
| Salud de compilación: Xcode, Bazel, Gradle | Hora de inserción del registro | Incluye inicio, excluye fin |
| Salud de compilación: Once | Hora de inicio de la ejecución | Incluye inicio, excluye fin |
| Duraciones de compilación de Xcode | Hora de inserción del registro | Excluye inicio y fin |
| Duraciones de prueba | Hora de ejecución registrada | Incluye inicio y fin |

### Variables del panel

Usa variables del panel para proyectos y filtros compatibles. Las variables de rama y carga de trabajo usan estas consultas:

| Variable | Consulta |
| --- | --- |
| Rama | `buildBranches account/project` |
| Carga de trabajo | `buildWorkloads account/project` |

Los filtros aceptan un único valor exacto. Para las variables de rama y carga de trabajo, establece el valor personalizado de la opción Todo a `__tuist_all__`. Los demás filtros usan su opción incorporada Cualquiera o un valor vacío. Las selecciones múltiples y las expresiones regulares no son compatibles.

## Reportar metadatos personalizados {#custom-metadata}

Las compilaciones de Xcode, Bazel y Gradle aceptan estos valores opcionales de metadatos:

| Clave | Valor aceptado |
| --- | --- |
| `tuist.workload` | Un nombre de carga de trabajo que reemplaza la agrupación predeterminada. |
| `tuist.failure_category` | `verification` o `infrastructure_tooling`. |
| `tuist.cache_work_avoided_ms` | Solo Gradle. Estimación de trabajo evitado reportada automáticamente, en milisegundos enteros de hasta 365 días. |
| `tuist.cache_time_saved_ms` | Milisegundos enteros de 0 a 31.536.000.000 (365 días). |

Proporciónalos a través de la configuración de metadatos personalizados de tu integración de compilación:

```json
{
  "custom_metadata": {
    "values": {
      "tuist.workload": "Release verification",
      "tuist.failure_category": "verification",
      "tuist.cache_time_saved_ms": "12000"
    }
  }
}
```

Reporta ahorros de caché solo cuando tengas una medición de tiempo transcurrido o una estimación documentada para esa compilación. Los aciertos de caché y las duraciones acumuladas de tareas por sí solas no pueden determinar los ahorros de tiempo transcurrido cuando las tareas se ejecutan concurrentemente. Los ahorros de caché faltantes permanecen desconocidos. Los metadatos de categoría de fallo faltantes recurren a la evidencia registrada, como se describe en [Sistemas de compilación](#build-systems). La retención de datos no cambia.

## Alertas y Slack {#alerts-and-slack}

Crea una regla de alerta gestionada por Grafana con una métrica numérica. Por ejemplo:

| Métrica | Identificador | Condición de ejemplo |
| --- | --- | --- |
| Tasa de éxito de compilación | `success_rate` | Por debajo del 99% |
| Compilaciones fallidas | `failed_builds` | Por encima de cero |
| Duración del percentil 90 | `p90` | Por encima del límite de duración de tu equipo |

Usa **Período completo** para un único valor durante la ventana de evaluación, o reduce una serie temporal a un único valor. Para consultas de duración en modo Período completo, selecciona una serie.

- Usa valores fijos de proyecto y filtro. Las variables del panel no están disponibles durante la evaluación de alertas en segundo plano.
- Usa consultas numéricas para las alertas. Para monitorizar una carga de trabajo, filtra una consulta de salud de compilación a esa carga de trabajo.
- Configura el comportamiento de la regla cuando no hay datos para intervalos sin compilaciones o ahorros de caché reportados.

Configura un [punto de contacto de Slack](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-slack/) y enruta la regla hacia él a través de la política de notificaciones de Grafana. Grafana envía las notificaciones y almacena las credenciales de Slack.

## Actualizar paneles existentes {#upgrading}

Los paneles de duración existentes conservan sus consultas, filtros, nombres de serie y unidades. Los paneles y variables de salud de Gradle guardados también siguen funcionando.

Importa el panel estándar por separado para usar las consultas compartidas de salud de compilación. Los paneles existentes no se migran automáticamente. Las consultas compartidas requieren un servidor Tuist que proporcione los endpoints de salud de compilación; las consultas de duración existentes siguen funcionando con servidores más antiguos.

## Requisitos {#requirements}

- Grafana 10.4 o superior.
- Un token de Tuist con permiso para leer los proyectos y métricas que quieres graficar. Consulta [Autenticación](#authentication) más abajo.

## Autenticación {#authentication}

Usa un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> para paneles y evaluación de alertas en segundo plano. Concede `project:builds:read` para métricas de compilación y `project:tests:read` para duraciones de prueba, y restringe el acceso a los proyectos que quieres graficar. Solo se requieren los ámbitos para las métricas que uses. Sigue las <.localized_link href="/guides/server/authentication#creating-an-account-token">instrucciones de creación de token</.localized_link> para generar uno.

La integración también acepta tokens de proyecto existentes para su propio proyecto y <.localized_link href="/guides/server/authentication#as-a-user">tokens de acceso de usuario</.localized_link> con los permisos de lectura del usuario. Los tokens de acceso de usuario tienen una vida corta. Grafana almacena el token que proporcionas y no lo actualiza ni reutiliza tu inicio de sesión local de Tuist; reemplázalo cuando caduque. Los tokens de cuenta te permiten controlar el acceso al proyecto, los permisos y la caducidad independientemente de la sesión de inicio de sesión de un usuario.

## Configuración {#configuration}

Añade la fuente de datos y configura:

| Campo | Ajuste guardado | Notas |
| --- | --- | --- |
| URL del servidor | `jsonData.url` | Por defecto es `https://tuist.dev`. |
| Token | `secureJsonData.apiToken` | Token bearer de Tuist, almacenado cifrado. |

Selecciona **Guardar y probar** para comprobar la conexión. Grafana enumera los proyectos accesibles y luego comprueba los permisos de lectura de compilación y prueba frente al primer proyecto.

## Instalación {#installation}

### Desde el catálogo de Grafana {#from-the-grafana-catalog}

Una vez publicado, instálalo como cualquier otra fuente de datos desde **Conexiones → Añadir nueva conexión → Tuist**, o con `grafana-cli plugins install tuist-metrics-datasource`.

### Antes de su publicación (Grafana autoalojado) {#before-it-is-published-self-hosted-grafana}

El plugin no está firmado hasta que se aprueba para el catálogo. En una instancia autoalojada puedes hacer lo siguiente:

- **Permitir sin firmar** — añade `tuist-metrics-datasource` a `allow_loading_unsigned_plugins` (o `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-metrics-datasource`) y coloca el plugin compilado en tu directorio de plugins.
- **Firmarlo de forma privada** para tus instancias — `npm run sign -- --rootUrls https://grafana.example.com` (la URL debe coincidir con la `root_url` de la instancia), y luego distribuye el zip.

[Grafana Cloud requiere plugins del catálogo](https://grafana.com/docs/grafana-cloud/learn-and-build/get-started/learn/find-and-use-plugins/) y no admite plugins sin firmar o cargados manualmente.
