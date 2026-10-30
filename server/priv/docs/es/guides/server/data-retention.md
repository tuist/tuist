---
{
  "title": "Retención de datos",
  "titleTemplate": ":title | Server | Guías | Tuist",
  "description": "Aprende cuánto tiempo conserva Tuist los artefactos descargables y los datos de actividad del panel."
}
---
# Retención de datos {#data-retention}

Tuist aplica políticas de retención independientes a los archivos de artefactos subidos y a los registros utilizados para los paneles y las analíticas. Eliminar un archivo de artefacto caducado no elimina los registros de analíticas asociados.

Para los archivos de artefactos, el servidor alojado de Tuist utiliza ventanas basadas en el plan con un límite máximo de 30 días. La limpieza de artefactos está desactivada por defecto en las instancias autoalojadas, donde los operadores pueden activarla y configurar una ventana independiente para cada tipo de artefacto admitido.

## Archivos de artefactos {#artifact-files}

### Servidor alojado de Tuist {#hosted-artifact-files}

Estas ventanas definen cuánto tiempo permanecen disponibles los archivos de artefactos en el servidor alojado de Tuist.

| Artefacto | Air y Open Source | Pro | Enterprise |
| --- | --- | --- | --- |
| Artefactos de caché, incluidos la caché de Xcode, la caché de módulos, la caché de Gradle, los archivos de caché remota de Bazel y los archivos de caché de GitLab CI de los Runners de Tuist | 14 días | 30 días | 30 días |
| Compilaciones de previsualizaciones de apps e iconos | 30 días | 30 días | 30 días |
| Archivos de compilación | 7 días | 30 días | 30 días |
| Artefactos de ejecución, incluidos paquetes de resultados y archivos de sesión | 7 días | 30 días | 30 días |
| Adjuntos de ejecuciones de tests | 30 días | 30 días | 30 días |
| Paquetes de fragmentos | 7 días | 14 días | 30 días |

El plan activo de la cuenta determina la ventana de retención del servicio alojado. Si una cuenta no tiene una suscripción activa, Tuist utiliza la ventana de retención de Air. Algunos tipos de artefactos utilizan ventanas más cortas porque se espera que se regeneren.

Los adjuntos de tests creados antes de que Tuist registrara un identificador de ejecución de test quedan excluidos de la eliminación automática. Sus archivos permanecen disponibles mientras Tuist evita realizar búsquedas ilimitadas de propiedad histórica durante la limpieza de retención.

### Instancias autoalojadas {#self-hosted-artifact-files}

La limpieza de artefactos en entornos autoalojados es opcional, configurable por separado para cada tipo de artefacto y no tiene un límite de 30 días. Consulta la <.localized_link href="/guides/server/self-host/server#artifact-retention">configuración de retención de artefactos autoalojados</.localized_link> para ver los tipos de artefactos admitidos y las opciones de despliegue.

## Datos del panel y de actividad {#dashboard-and-activity-data}

Los registros del panel y de actividad tienen políticas de retención independientes de la limpieza de archivos de artefactos. Las ventanas siguientes no varían según el plan alojado, incluido Enterprise.

### Análisis de tests y compilaciones de Xcode {#xcode-build-and-test-insights}

Los registros principales de compilación y tests de Xcode no tienen actualmente un calendario fijo de eliminación basado en el tiempo. Otros datos de informes, como los pasos de la línea temporal y las métricas de la máquina, caducan por separado:

| Datos | Retención |
| --- | --- |
| Resúmenes de compilación, registros de compilación por archivo y por objetivo, e incidencias de compilación | Sin calendario fijo de eliminación basado en el tiempo |
| Ejecuciones de tests, resultados de módulos y suites, y resultados de tests individuales | Sin calendario fijo de eliminación basado en el tiempo |
| Pasos de la línea temporal de compilación y sus registros capturados | 90 días |
| Métricas de la máquina de compilación | 90 días |
| Registros del grafo de proyectos de Xcode | 30 días |

Estos registros son independientes de los archivos de compilación descargables, los paquetes de resultados y los adjuntos de tests cubiertos por las [ventanas de retención de archivos de artefactos](#hosted-artifact-files). En Enterprise, esos archivos se conservan durante 30 días; los registros de compilación y tests asociados permanecen disponibles después de que los archivos caduquen. Que un registro no tenga un calendario fijo de eliminación basado en el tiempo no garantiza su disponibilidad permanente.

### Otros datos del panel y de actividad {#other-dashboard-and-activity-data}

| Datos | Retención |
| --- | --- |
| Registros de compilación de Gradle, registros de tareas, registros de eventos de caché, registros de compilación de Mix, registros de archivos compilados, registros y diagnósticos de pasos de compilación, registros de compilación de Cargo (incluidas las mediciones agregadas de la caché de compilación) y observaciones del compilador, invocaciones de Bazel, perfiles de traza de Bazel, pasos de perfil indexados y diagnósticos de acciones, registros pendientes de ingesta de perfiles y tests de Bazel, registros de invocación de Bazel y observaciones de la caché de acciones remotas de Bazel | 90 días |
| Historial de compilación de módulos y caché de Xcode en páginas de detalles persistentes de módulos | 30 días |
| Observaciones de tareas, acciones Once declaradas, acciones BEP de Bazel, archivos compilados y módulos en páginas de detalles persistentes | 90 días, excepto los módulos de Xcode mencionados arriba |
| Metadatos de identidad persistentes de tarea/acción/módulo/archivo | 365 días sin una observación |
| Registros de trabajos de Runner, registros archivados de Runner y métricas de máquina de trabajos de Runner | 90 días |
| Historial de entrega de webhooks | Sin calendario fijo de eliminación |

Las URL de detalles persistentes no dependen de que una compilación concreta siga estando disponible. Sus metadatos de identidad pueden sobrevivir a observaciones individuales, por lo que una página de detalles puede no tener historial en el periodo seleccionado. El nuevo historial se indexa a partir de los informes recibidos después de desplegar la funcionalidad; el historial existente a nivel de ejecución no se copia retroactivamente.

Las tablas de registros operativos internas `system.*` de ClickHouse se configuran en la capa de ClickHouse, no mediante la política de retención de datos de producto de Tuist. Por defecto, no tienen límite; las configuraciones empaquetadas de Docker Compose autoalojado y Helm integrado de ClickHouse pueden establecer un tope, como se describe en <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">limitar la retención de registros operativos</.localized_link>.
