---
{
  "title": "Servidor",
  "titleTemplate": ":title | Autoalojamiento | Servidor | Guías | Tuist",
  "description": "Aprende a desplegar el servidor de Tuist en tu infraestructura."
}
---
# Servidor {#server}

Ofrecemos una versión autoalojada del servidor de Tuist para organizaciones que requieren más control sobre su infraestructura. Esta versión te permite alojar Tuist en tu propia infraestructura, garantizando que tus datos permanezcan seguros y privados.

> [!WARNING]
> **Licencia obligatoria**
>
> El autoalojamiento de Tuist requiere una licencia de pago legalmente válida. La versión on-premise de Tuist está disponible únicamente para organizaciones en el plan Enterprise. Si te interesa esta versión, contacta con [contact@tuist.dev](mailto:contact@tuist.dev).

> [!WARNING]
> **Servicio de caché heredado**
>
> La antigua tecnología de nodos de caché autoalojados está obsoleta para nuevas instalaciones. Consulta la <.localized_link href="/guides/features/cache/self-hosting">guía de caché autoalojado</.localized_link> para la infraestructura actual de caché autoalojada.
>
> Los despliegues existentes aún pueden consultar la documentación fuente heredada en el visor de Markdown de GitHub: [nodos de caché](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/self-host.md) y [arquitectura de caché](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/cache/architecture.md).

## Cadencia de lanzamientos {#release-cadence}

El servidor de Tuist y el servidor de caché Kura se distribuyen a través de tres canales de imágenes GHCR: **canary** (cada commit en `main`), **candidato a lanzamiento** (generado cada lunes, permanece una semana) y **estable** (promovido el lunes siguiente). Solo los lanzamientos estables mueven `:latest` y se resuelven por defecto; las versiones canary y candidatas a lanzamiento son prereleases de GitHub a las que puedes optar fijando su etiqueta. El servidor y Kura siguen el mismo tren semanal, al unísono con el [calendario de lanzamientos de la CLI de Tuist](/en/cli/release-channels).

Seguimos el [versionado semántico](https://semver.org/) para garantizar un versionado predecible y compatibilidad. El componente mayor se utiliza para señalar cambios incompatibles en el servidor de Tuist que requerirán coordinación con usuarios autoalojados; no deberías esperar que lo utilicemos, y en caso de que fuera necesario, ten la seguridad de que trabajaremos contigo para hacer la transición sin problemas.

Consulta la página de <.localized_link href="/guides/server/self-host/release-channels">canales de lanzamiento</.localized_link> para saber cómo se genera cada canal, cómo fijar uno en tu despliegue y la estrategia recomendada para mantener la producción en una línea estable de movimientos lentos mientras un entorno de staging prueba el próximo lanzamiento.

## Límite de actualización y retroceso de OAuth {#oauth-upgrade-and-rollback-boundary}

La eliminación de la caché de entidades de OAuth requiere una actualización escalonada para las instalaciones existentes. Antes de desplegar una versión que detenga las invalidaciones de caché de OAuth, despliega primero la release de compatibilidad de lectura autoritativa del [#14040](https://github.com/tuist/tuist/pull/14040) en **todos los lectores y escritores de OAuth**. Esta etapa de compatibilidad aparece por primera vez en la línea de lanzamiento **1.355**: `ghcr.io/tuist/tuist:1.355.0-rc.1` la contiene; los despliegues de producción deben usar una release estable `1.355.x` una vez promovida. Las instalaciones en la 1.354 o anteriores deben completar esta etapa antes de actualizar a una release posterior que contenga la eliminación. Mantén la línea 1.355 solo para compatibilidad: no hagas backport de la eliminación de invalidaciones a ella.

El commit de compatibilidad original también está disponible como `ghcr.io/tuist/tuist:sha-c8e54471a425`. Otra imagen es adecuada como etapa de compatibilidad solo si preserva las lecturas autoritativas **y mantiene las invalidaciones heredadas** mientras permanecen consumidores antiguos. Ejecuta las migraciones normales de base de datos de esa etapa antes de servir tráfico, incluido el índice de búsqueda de tokens de actualización.

Comprueba todas las réplicas web, workers en segundo plano, trabajos programados e imágenes de procesadores fijadas por separado en cada entorno. Espera a que finalice el despliegue de compatibilidad y verifica que no queden binarios que lean la caché antes de eliminar las invalidaciones. No permitas que una etiqueta de imagen flotante omita esta etapa durante una actualización automatizada. Las instalaciones nuevas sin consumidores antiguos no necesitan un despliegue intermedio.

> [!WARNING]
> **Mantén un objetivo de retroceso con lectura autoritativa**
>
> Una vez eliminadas las invalidaciones, un retroceso rodante ordinario debe apuntar al #14040 u otra versión con lectura autoritativa. Las entradas de caché de OAuth retenidas pueden estar obsoletas incluso después de que todos los procesos sin invalidación se hayan detenido, y una réplica que lee la caché reiniciada puede importarlas desde sus pares.
>
> Un retroceso adicional requiere detener y drenar **todos** los consumidores de OAuth sin invalidación, luego limpiar o reemplazar **cada** participante de caché Boruta retenido antes de iniciar cualquier consumidor que lea la caché. Impide que los participantes retenidos se reincorporen. Drenar solo el ingreso o reiniciar solo las réplicas web es insuficiente; coordina esta recuperación con tu contacto de soporte de Tuist en lugar de limpiar cachés o hacer retrocesos de migraciones de base de datos automáticamente.

## Agrupamiento de múltiples réplicas {#multi-replica-clustering}

Los despliegues web compatibles con múltiples réplicas requieren agrupamiento Erlang para notificaciones Phoenix PubSub y Oban PG entre réplicas, no como autoridad para la autenticación. El chart rechaza múltiples réplicas, incluido un autoscaler que pueda crecer más allá de una réplica, cuando `server.cluster.enabled` es false. Los despliegues sin agrupamiento aceptados anteriormente deben planificar esta actualización en lugar de omitir la protección. Completa la <.localized_link href="/guides/server/self-host/server#oauth-upgrade-and-rollback-boundary">secuencia de actualización de OAuth</.localized_link>, incluida la eliminación de invalidaciones, antes de cambiar la pertenencia.

Crea un Secret privado de cookie en el namespace de release usando tu gestor de secretos, luego configura su nombre y clave:

```yaml
server:
  replicaCount: 2
  cluster:
    enabled: true
    distributionPort: 9100
    cookieExistingSecret: tuist-server-cluster
    cookieExistingSecretKey: release-cookie
```

La cookie debe tener alta entropía y ser compartida por todas las réplicas web participantes. Nunca uses la cookie incrustada en una imagen publicada: poseer una cookie de distribución concede ejecución remota en sus nodos. El inicio de releases distribuidas ahora rechaza una `RELEASE_COOKIE` privada faltante o un puerto no válido, incluido `RELEASE_DISTRIBUTION=name` configurado explícitamente o `sname` sin descubrimiento DNS. Los despliegues sin chart también deben configurar `TUIST_CLUSTER_DNS_SERVICE`, `TUIST_CLUSTER_APP_NAME` y la IP del pod/nombre del nodo de forma consistente. El descubrimiento utiliza actualmente registros A IPv4.

Con un `helm upgrade` conectado al servidor ordinario, dejar `cookieExistingSecret` vacío crea un Secret de cookie y reutiliza su valor actual en actualizaciones posteriores. `helm template` offline, Argo CD y otros renderizadores GitOps sin búsqueda activa de Secrets no pueden preservar ese valor generado; deben usar `cookieExistingSecret` respaldado por un Secret estable gestionado por separado. No cambies la clave de la cookie para rotar implícitamente un clúster activo. La rotación de cookies necesita una migración/reinicio coordinado de cada participante; actualizar un Secret por sí solo no actualiza los procesos existentes.

El primer despliegue desde cookies integradas en la imagen forma islas de pertenencia antiguas/nuevas separadas hasta que todas las réplicas web usen el Secret privado. Planifica una ventana de migración para actualizaciones en tiempo real. Los despliegues rolling posteriores forman clústeres de versiones mixtas, así que valida PubSub, notificaciones Oban y reemplazo de pares entre las versiones antiguas/nuevas reales. Estas notificaciones no son garantías de entrega duradera. Mantén una imagen de rollback con lectura autoritativa y conserva la misma cookie privada al hacer rollback a una versión compatible.

Permite EPMD (TCP 4369) y el puerto de distribución configurado solo entre pares de servidor de confianza, nunca desde cargas de trabajo de inquilinos o la red pública. Verifica el aislamiento real de entrada/salida en tu entorno; renderizar una NetworkPolicy no prueba su aplicación ni la accesibilidad del backend. Un canary de dos réplicas bajo carga continua debe superar la unión, el reemplazo rolling y la recuperación ante fallos antes de su promoción. DNS se usa para descubrir pares, no para desconectar nodos sanos por una respuesta fallida o parcial transitoria; la pérdida real de nodos y la prevención de particiones OTP siguen aplicándose. libcluster puede registrar aún una operación "desconectada" exitosa para la callback de retención sin cerrar una conexión; establece la pertenencia real a partir de eventos de nodo arriba/abajo o `Node.list()`, no solo de esa línea de registro.

## Despliegue continuo {#continuous-deployment}

Recomendamos mantener producción fijada a una línea menor estable (por ejemplo `ghcr.io/tuist/tuist:1.351`), para que las actualizaciones diarias incluyan solo correcciones retroportadas. Las líneas estables se promueven cada lunes a las 06:00 UTC tras una semana de prueba en el canal de release-candidate; un entorno de staging en canary o en la etiqueta release-candidate actual detectará regresiones antes de que lleguen a tus usuarios. Consulta <.localized_link href="/guides/server/self-host/release-channels">Canales de release</.localized_link> para ver la estrategia de fijación recomendada.

Si prefieres incorporar nuevas funcionalidades a medida que se estabilizan sin tocar tus manifiestos, fija `:latest`. La etiqueta cambia una vez por semana el lunes por la mañana, así que programa tu ventana de despliegue en consecuencia. Aquí tienes un ejemplo de flujo de trabajo de GitHub Actions que comprueba y despliega la última imagen estable con esa cadencia:

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 8 * * 1' # Mondays 08:00 UTC, after the weekly stable promote
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

<span id="network-trusted-report-publishing"></span>
<span id="network-trusted-cache-access"></span>

## Acceso de red confiable {#network-trusted-access}

Las instalaciones autoalojadas pueden permitir a desarrolladores en una red de confianza enviar análisis, usar la caché o ambas cosas sin iniciar sesión. El panel de control y la administración siguen requiriendo autenticación.

Habilita solo las capacidades que necesites:

| Variable de entorno del servidor | Permite sin inicio de sesión |
| --- | --- |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` | Enviar análisis de compilación y tests |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS=true` | Leer y escribir salidas de compilación en caché |

Ambas configuraciones están **desactivadas por defecto**, son independientes y se aplican a toda la instancia en todas las cuentas y proyectos, incluidos los privados. No están disponibles en Tuist alojado y no sustituyen la licencia de autoalojamiento.

El antiguo nombre `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING` sigue siendo un fallback de compatibilidad cuando `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` no está establecido.

> [!WARNING]
> Habilita estas configuraciones solo detrás de un límite impuesto de red de oficina o VPN. Cualquiera que pueda alcanzar un endpoint habilitado puede enviar informes o, con el acceso a caché habilitado, leer y sobrescribir salidas en caché. Esto permite telemetría falsificada, envenenamiento de caché y agotamiento de capacidad. Las respuestas de los informes también pueden revelar identificadores de proyectos privados y sistemas de compilación. Tuist no verifica la pertenencia a la VPN ni confía en las cabeceras IP reenviadas como prueba de pertenencia.

### Configurar la instancia {#network-trusted-instance-configuration}

1. Restringe el servidor Tuist, cada listener HTTP/gRPC de Kura y cualquier entrada Bazel BES a tu red de confianza usando un firewall o entrada privada.
2. Actualiza cada réplica del servidor y de Kura antes de actualizar los clientes. Mantén la autenticación de Kura habilitada con `KURA_AUTH_TUIST_URL` y sus credenciales del plano de control; deshabilitarla omite estas restricciones. Configura tu endpoint de caché usando la <.localized_link href="/guides/features/cache/self-hosting">guía de caché autoalojada</.localized_link>.
3. Establece las variables deseadas anteriores en cada réplica relevante del servidor Tuist, luego reinícialas o vuelve a desplegarlas. Solo el valor exacto `true` habilita una configuración. No hay un interruptor en el panel ni una bandera separada de Kura.

### Configurar los clientes {#network-trusted-client-configuration}

Configura la URL final del servidor autoalojado y el proyecto en cada cliente compatible. Los clientes descubren automáticamente qué capacidades están habilitadas cuando faltan las credenciales; no se necesita opt-in del cliente. El descubrimiento no sigue redirecciones. Las credenciales existentes siguen en uso, y las credenciales inválidas o con refresco fallido provocan un error en lugar de un fallback anónimo. Vuelve a iniciar sesión o cierra sesión explícitamente para recuperarte.

Antes de habilitar el acceso a análisis, actualiza todas las herramientas que comparten credenciales a versiones que preserven credenciales corruptas o rechazadas, rechacen directorios de credenciales ilegibles y omitan orígenes Git de informes sin firmar. Las herramientas antiguas pueden eliminar credenciales y permitir inadvertidamente un fallback anónimo; una actualización solo del servidor no puede arreglar esto. Si al servidor le falta soporte de descubrimiento o se hace rollback a una versión anterior, los clientes deben autenticarse. La antigua configuración de cliente `TUIST_NETWORK_TRUSTED_PUBLISHING` ya no aplica.

- **Análisis:** Envía solo informes completados de Xcode, Gradle, Elixir/Mix y Bazel, sin acceso a archivo, adjuntos, cobertura, planificación de shards o informes existentes. Las reclamaciones de actor no están verificadas; la telemetría sin firmar no impulsa evidencia de test confiable ni automatización. Consulta las guías de <.localized_link href="/guides/features/build-insights/xcode#network-trusted-publishing">Xcode</.localized_link>, <.localized_link href="/guides/features/build-insights/gradle#network-trusted-publishing">Gradle</.localized_link> y <.localized_link href="/guides/features/build-insights/elixir#network-trusted-publishing">Elixir</.localized_link> para detalles de configuración del cliente y privacidad.
- **Caché:** Soporta caché de compilación/módulo CLI, caché de Bazel y caché de tareas de Gradle. Las purgas de caché y las descargas de Remote Asset siguen requiriendo credenciales. Los clientes sin soporte deben continuar autenticándose.
- **Bazel:** Los informes requieren un `TUIST_BAZEL_BES_BACKEND` explícito y un Kura compatible. Las opciones de caché e informes se habilitan independientemente. Vuelve a ejecutar `tuist bazel setup` después de cambiar las credenciales o cualquiera de las configuraciones; vuelve a ejecutar `tuist cache config` para cambios en la configuración de la caché de compilación.

Las solicitudes de informe están limitadas a 8 MB, 60 solicitudes por minuto y 10.000 por día por proyecto. Configura Valkey compartido para cuotas en todo el despliegue con múltiples réplicas; de lo contrario, los límites son por proceso. Si un backend de cuota compartida configurado no está disponible, los informes sin firmar son rechazados. Añade también límites de conexión de entrada, cuerpo y tasa.

### Deshabilitar acceso de red confiable {#disable-network-trusted-publishing}

Establece la variable correspondiente a `false` y luego reinicia **cada réplica del servidor relevante**. Las réplicas antiguas pueden seguir aceptando solicitudes sin credenciales hasta que sean reemplazadas. El acceso a la caché se detiene para las nuevas solicitudes dentro de los 60 segundos posteriores al cambio de la última réplica; las transferencias en curso no se cancelan. Bloquea el tráfico en el ingress primero si se requiere una revocación inmediata. Los informes existentes conservan su visibilidad y retención habituales, y los clientes autenticados continúan funcionando.

## Requisitos de ejecución {#runtime-requirements}

Esta sección describe los requisitos para alojar el servidor de Tuist en tu infraestructura.

### Matriz de compatibilidad {#compatibility-matrix}

El servidor de Tuist ha sido probado y es compatible con las siguientes versiones mínimas:

| Componente | Versión mínima | Notas |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | {{minimum_supported_clickhouse_version}} | Requerido para análisis |

### Ejecutar imágenes virtualizadas con Docker {#running-dockervirtualized-images}

Distribuimos el servidor como una imagen de [Docker](https://www.docker.com/) a través del [Registro de Contenedores de GitHub](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Para ejecutarlo, tu infraestructura debe soportar la ejecución de imágenes de Docker. Ten en cuenta que la mayoría de los proveedores de infraestructura lo soportan porque se ha convertido en el contenedor estándar para distribuir y ejecutar software en entornos de producción.

### Base de datos Postgres {#postgres-database}

Además de ejecutar las imágenes de Docker, necesitarás una [base de datos Postgres](https://www.postgresql.org/) para almacenar datos relacionales. La mayoría de los proveedores de infraestructura incluyen bases de datos Postgres en su oferta (por ejemplo, [AWS](https://aws.amazon.com/rds/postgresql/) y [Google Cloud](https://cloud.google.com/sql/docs/postgres)).

> [!NOTE]
> **Migraciones**
>
> El punto de entrada de la imagen de Docker ejecuta automáticamente cualquier migración de esquema pendiente antes de iniciar el servicio.


### Base de datos ClickHouse {#clickhouse-database}

Tuist utiliza [ClickHouse](https://clickhouse.com/) para almacenar y consultar grandes cantidades de datos de análisis. ClickHouse es **requerido** para funcionalidades como los análisis de compilaciones. Puedes elegir si autoalojar ClickHouse o usar su servicio alojado.

> [!NOTE]
> **Migraciones**
>
> El punto de entrada de la imagen de Docker ejecuta automáticamente cualquier migración de esquema de ClickHouse pendiente antes de iniciar el servicio.

Las configuraciones embebidas de ClickHouse incluidas en Docker Compose y Helm reducen el nivel de registro de texto de ClickHouse desde el valor predeterminado `trace` de la imagen hasta `information`, que es de donde proviene la mayor parte del volumen de `system.text_log`. Ambas también pueden limitar las tablas de registros operativos `system.*` propias de ClickHouse, que de otro modo son ilimitadas, pero esto está desactivado por defecto; consulta más abajo. Los despliegues externos de ClickHouse deben configurar estos registros operativos directamente en su servicio de ClickHouse.

#### Topología de replicación de ClickHouse {#clickhouse-replication-topology}

ClickHouse con múltiples réplicas detrás de Tuist solo se admite en ClickHouse Cloud. ClickHouse autogestionado es de una sola réplica.

Las migraciones de ingesta emiten un motor `MergeTree` simple. En Cloud, esto se convierte transparentemente en un `SharedMergeTree`, por lo que las escrituras aterrizan en almacenamiento de objetos compartido y funciona cualquier número de réplicas. En ClickHouse autogestionado, `MergeTree` escribe en el disco local de una sola réplica; una configuración de múltiples réplicas dividirá la ingesta silenciosamente entre las réplicas o rechazará el CREATE con `UNKNOWN_STORAGE: Only tables with a Replicated engine or tables which do not store data on disk are allowed in a Replicated database.` dependiendo de cómo esté configurado `database_replicated_allow_only_replicated_engine` en el usuario que se conecta.

Ejecuta un shard con una réplica en ClickHouse autogestionado y realiza copias de seguridad regulares del directorio de datos de ClickHouse. No hay una segunda réplica a la que recurrir si se pierde el nodo.

#### Limitar la retención de registros operativos {#capping-operational-log-retention}

La retención se puede aplicar a `system.text_log`, `system.query_log`, `system.query_thread_log`, `system.query_views_log`, `system.trace_log`, `system.metric_log`, `system.asynchronous_metric_log` y `system.part_log`.

Activarlo es un paso único e irreversible en una instancia que ya tiene datos, por lo que ninguno de los paquetes lo hace por ti. Cualquier ventana de retención hace que esas definiciones de tabla dejen de coincidir con su configuración, por lo que ClickHouse renombra cada una y crea una nueva tabla, como se describe en [tablas de registros suplantadas](#superseded-log-tables). La generación dejada atrás contiene todo lo acumulado hasta el momento y no tiene retención propia, por lo que, a menos que la recuperes en el mismo paso, permanecerá en el disco permanentemente y la nueva ventana solo limitará las filas escritas a partir de entonces. Habilita ambos juntos:

```yaml
clickhouse:
  embedded:
    systemLogs:
      ttlDays: 14
      supersededTables: delete
```

Ese único `helm upgrade` es autosuficiente, porque mover `ttlDays` de vacío a establecido añade el montaje drop-in y reinicia el pod de ClickHouse: se reinicia, suplanta las tablas y el Job posterior a la actualización las elimina. Despliega con `helm upgrade --wait` para que el pod se reinicie antes de que se ejecute el Job; de lo contrario, las generaciones aparecen después de que haya buscado, y el siguiente `helm upgrade` las recuperará en su lugar.

Con Docker Compose, descomenta el volumen `clickhouse-log-ttl.xml` en el servicio `clickhouse` en `docker-compose.yml` y establece ambas variables en `.env`:

```bash
CLICKHOUSE_SYSTEM_LOG_TTL_DAYS=14
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

Una vez recuperado el espacio, puedes volver a establecer `supersededTables`/`CLICKHOUSE_SUPERSEDED_LOG_TABLES` a `ignore`, para que una futura actualización de ClickHouse no descarte el historial por sí misma.

#### Tablas de registros suplantadas {#superseded-log-tables}

ClickHouse comprueba al inicio si cada tabla de registros del sistema sigue coincidiendo con su configuración. Cuando no coincide, renombra la tabla existente a `system.<name>_0`, luego `_1`, `_2`, y así sucesivamente, y crea una nueva. Esto ocurre cuando cambias la ventana de retención y en cualquier actualización de ClickHouse que cambie el esquema de un registro del sistema.

Renombrar una tabla no copia sus datos, por lo que no consume disco adicional. Lo que ocurre con la tabla suplantada después depende de la tabla de la que proviene, porque mantiene la retención que tenía la tabla activa en el momento en que fue suplantada. La primera vez que habilitas la retención, la tabla que está siendo suplantada no tiene ninguna, por lo que conserva todo el historial acumulado hasta el momento indefinidamente. Un cambio posterior en la ventana suplanta una tabla que ya tiene un TTL, por lo que esas expiran por sí solas y dejan una tabla vacía. ClickHouse nunca elimina las tablas en sí, por lo que en una instancia de larga duración se acumulan de todas formas.

Las tablas suplantadas se conservan por defecto, para que una actualización nunca descarte el historial operativo por sí misma. Establece la política a `delete` para eliminarlas en su lugar, lo cual ocurre en `docker compose up` y en cada `helm upgrade`:

```bash
CLICKHOUSE_SUPERSEDED_LOG_TABLES=delete
```

Con el chart de Helm, configura la misma política como un valor:

```yaml
clickhouse:
  embedded:
    systemLogs:
      supersededTables: delete
```

Eliminar una tabla suplantada recupera su espacio en disco. La tabla activa nunca se toca, ni tampoco las filas escritas desde que fue suplantada.

Para recuperar el espacio una vez sin cambiar la política, elimina las tablas manualmente:

```sql
SELECT name FROM system.tables WHERE database = 'system' AND match(name, '_log_[0-9]+$');
DROP TABLE IF EXISTS system.text_log_0 SYNC;
```

La base de datos `system` utiliza el motor `Atomic`, que pospone un `DROP TABLE` simple mediante `database_atomic_delay_before_drop_table_sec` (ocho minutos por defecto). `SYNC` elimina los datos de inmediato, que es lo que deseas al eliminarlas porque el disco está lleno.


### Almacenamiento {#storage}

También necesitarás una solución para almacenar archivos (por ejemplo, binarios de frameworks y bibliotecas). El servidor de Tuist admite almacenamiento compatible con S3 y Azure Blob Storage para artefactos propiedad del servidor.

> [!TIP]
> **Caché optimizada**
>
> Si tu objetivo principal es reducir la latencia de la caché, es posible que no necesites autoalojar todo el servidor. Puedes desplegar nodos Kura autoalojados cerca de tu red de CI o de desarrolladores y conectarlos al servidor de Tuist alojado o a tu servidor autoalojado.
>
> Consulta la <.localized_link href="/guides/cache/self-host">guía de caché autoalojada</.localized_link>.


### Nodos Kura autoalojados {#self-hosted-cache-nodes}

Para usar nodos Kura autoalojados con un servidor de Tuist autoalojado:

1. Configura `KURA_CONTROL_PLANE_CLIENT_ID` y `KURA_CONTROL_PLANE_CLIENT_SECRET` en el servidor de Tuist. El ID de cliente **debe ser un UUID**. Genera el UUID y un secreto aleatorio usando los comandos de la <.localized_link href="/guides/cache/self-host#control-plane-client">guía de caché autoalojada</.localized_link> y guárdalos en tus secretos de despliegue.
2. Despliega los nodos Kura siguiendo la <.localized_link href="/guides/cache/self-host">guía de caché autoalojada</.localized_link>, usando las mismas credenciales del plano de control.
3. Configura cada nodo Kura con `KURA_REGISTRATION_URL` y `KURA_ADVERTISED_HTTP_URL`. Los latidos de registro indican al servidor qué extremos de Kura listos y orientados al cliente puede anunciar a la CLI.

## Configuración {#configuration}

La configuración del servicio se realiza en tiempo de ejecución mediante variables de entorno. Dada la naturaleza sensible de estas variables, recomendamos cifrarlas y almacenarlas en soluciones seguras de gestión de contraseñas. Ten la seguridad de que Tuist maneja estas variables con sumo cuidado, asegurando que nunca se muestren en los registros.

> [!NOTE]
> **Comprobaciones de inicio**
>
> Las variables necesarias se verifican al inicio. Si falta alguna, el inicio fallará y el mensaje de error detallará las variables ausentes.


### Configuración de la licencia {#license-configuration}

Como usuario on-premise, recibirás una licencia que deberás exponer como variable de entorno. La licencia se utiliza para validar el despliegue y asegurar que el servicio se ejecuta dentro de los términos del acuerdo.

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | La licencia proporcionada después de firmar el acuerdo de nivel de servicio. Acepta tanto la clave de licencia estándar como el certificado codificado en base64 utilizado en entornos aislados donde el servidor no puede contactar con servicios externos. | Sí | | `******` |

> [!WARNING]
> **Fecha de caducidad**
>
> Las licencias tienen una fecha de caducidad. Los usuarios recibirán una advertencia al usar comandos de Tuist que interactúan con el servidor si la licencia caduca en menos de 30 días. Si estás interesado en renovar tu licencia, ponte en contacto con [contact@tuist.dev](mailto:contact@tuist.dev).


### Configuración del entorno base {#base-environment-configuration}

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | La URL base para acceder a la instancia desde Internet | Sí | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | La clave que se utiliza para cifrar información (por ejemplo, sesiones en una cookie) | Sí | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | Pepper para generar contraseñas hash | No | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | Clave secreta para generar tokens aleatorios | No | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | Clave de 32 bytes para cifrado AES-GCM de datos sensibles | No | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_USE_IPV6` | Cuando es `1`, configura la aplicación para usar direcciones IPv6 | No | `0` | `1`|
| `TUIST_LOG_LEVEL` | El nivel de registro que se utiliza para la aplicación | No | `info` | [Niveles de registro](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | El slug de tu aplicación de GitHub, obtenido de `https://github.com/apps/<slug>`. Necesario para instalar la aplicación. Consulta <.localized_link href="/guides/server/self-host/server#platform-github">GitHub</.localized_link> | No | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | La clave privada codificada en base64 utilizada por la aplicación de GitHub para desbloquear funcionalidades adicionales, como publicar comentarios automáticos en PRs | No | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | La clave privada utilizada por la aplicación de GitHub para desbloquear funcionalidades adicionales, como publicar comentarios automáticos en PRs. **Recomendamos usar la versión codificada en base64 para evitar problemas con caracteres especiales** | No | `-----BEGIN RSA...` | |
| `TUIST_OPERATOR_EMAIL_DOMAIN` | Los usuarios confirmados cuya dirección de correo electrónico termina en `@<this-domain>` pueden acceder a las URLs de operaciones (`/ops/*`) | No | `tuist.dev` | `example.com` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | Una etiqueta que se muestra como insignia en la barra de navegación del panel para identificar la instancia del servidor (por ejemplo, un número de versión o nombre de rama) | No | Rama de Git en desarrollo | `v1.2.3` |
| `TUIST_WEB` | Habilitar el endpoint del servidor web | No | `1` | `1` o `0` |
| `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS` | Permitir enviar análisis de compilación y tests sin iniciar sesión. Consulta [Acceso confiable por red](#network-trusted-access) para conocer los requisitos de configuración y seguridad. | No | `false` | `true` |
| `TUIST_NETWORK_TRUSTED_CACHE_ACCESS` | Permitir lecturas y escrituras en caché sin iniciar sesión. Consulta [Acceso confiable por red](#network-trusted-access) para conocer los requisitos de configuración y seguridad. | No | `false` | `true` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | El endpoint gRPC de un OpenTelemetry Collector al que enviar trazas | No | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | La URL base de un endpoint compatible con Loki para enviar registros (por ejemplo, Grafana Alloy o Loki) | No | | `http://localhost:3100` |

> [!WARNING]
> **Servir la aplicación sobre HTTPS**
>
> Las cookies de sesión están marcadas como `Secure`, por lo que los navegadores las descartan sobre `http://` simple y los usuarios no pueden iniciar sesión. Termina TLS delante del servidor (un proxy inverso con un certificado de tu CA interna es suficiente) y establece `TUIST_APP_URL` en la URL `https://`, incluso para despliegues internos o solo VPN.

### Configuración de la base de datos {#database-configuration}

Las siguientes variables de entorno se utilizan para configurar la conexión a la base de datos:

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | La URL para acceder a la base de datos Postgres. Ten en cuenta que la URL debe contener la información de autenticación | Sí | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_SCHEMA` | Esquema de PostgreSQL utilizado por las tablas de la aplicación de Tuist. Configúralo cuando tu política de base de datos no permita usar el esquema `public`. El nombre del esquema debe ser un identificador de PostgreSQL sin comillas. | No | `public` | `tuist` |
| `TUIST_MIGRATION_DATABASE_URL` | URL opcional de Postgres utilizada únicamente por `Tuist.Release.migrate`. Establécela como una URL de rol propietario cuando `DATABASE_URL` apunte a un rol de ejecución con menos privilegios. | No | `DATABASE_URL` | `postgres://owner:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_DATABASE_RUNTIME_ROLE` | Rol de ejecución de Postgres al que las migraciones deben otorgar privilegios sobre las tablas de la aplicación una vez finalizadas. Úsalo junto con `TUIST_MIGRATION_DATABASE_URL` cuando el servidor web no deba conectarse como propietario del esquema. | No | | `tuist_web` |
| `TUIST_CLICKHOUSE_URL` | La URL para acceder a la base de datos ClickHouse. Ten en cuenta que la URL debe contener la información de autenticación | No | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | Cuando es verdadero, utiliza [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) para conectarse a la base de datos | No | `1` | `1` |
| `TUIST_DATABASE_POOL_SIZE` | El número de conexiones que se mantienen abiertas en el pool de conexiones | No | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | El intervalo (en milisegundos) para comprobar si todas las conexiones obtenidas del pool tardaron más que el intervalo de cola [(Más información)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | No | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | El tiempo umbral (en milisegundos) en la cola que el pool utiliza para determinar si debe empezar a descartar nuevas conexiones [(Más información)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | No | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | Intervalo de tiempo en milisegundos entre vaciados del búfer de ClickHouse | No | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | Tamaño máximo del búfer de ClickHouse en bytes antes de forzar un vaciado | No | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | Número de procesos de búfer de ClickHouse que se ejecutan | No | `5` | `5` |

Cuando `TUIST_DATABASE_SCHEMA` no es `public`, las migraciones de release crean el esquema si aún no existe antes de ejecutar la cadena de migraciones de Ecto. Si el rol de migración no puede crear esquemas, crea el esquema previamente y haz que el rol de migración sea su propietario.

Tuist apunta la conexión al esquema personalizado estableciendo el `search_path` de sesión. Algunas configuraciones de Postgres con pooling o proxy (por ejemplo, PgBouncer o bases de datos gestionadas que restringen los parámetros de inicio) no aplican esto y la sesión vuelve a `public`, lo cual se manifiesta durante las migraciones como `permission denied for schema public`. Al conectarse a través de una configuración de este tipo, fija el esquema en el propio rol para que cada sesión comience en él independientemente del proxy:

```sql
CREATE SCHEMA IF NOT EXISTS tuist AUTHORIZATION <migration_role>;
ALTER ROLE <migration_role> IN DATABASE <database> SET search_path = tuist;
-- If the web server connects as a separate runtime role (TUIST_DATABASE_RUNTIME_ROLE):
ALTER ROLE <runtime_role> IN DATABASE <database> SET search_path = tuist;
```

### Configuración del entorno de autenticación {#authentication-environment-configuration}

Facilitamos la autenticación a través de [proveedores de identidad (IdP)](https://en.wikipedia.org/wiki/Identity_provider). Para utilizarla, asegúrate de que todas las variables de entorno necesarias para el proveedor elegido estén presentes en el entorno del servidor. La **falta de variables** hará que Tuist omita ese proveedor.

#### Correo electrónico y contraseña {#email-and-password}

El inicio de sesión con correo electrónico y contraseña y el registro autoservicio están integrados y habilitados por defecto. En una instancia donde quieras requerir un proveedor de identidad (por ejemplo, al imponer SSO), puedes desactivarlos por completo. Esto elimina el formulario de correo/contraseña, el enlace de registro y el flujo de restablecimiento de contraseña de la experiencia de inicio de sesión, y cierra todos los endpoints del servidor correspondientes, incluido el endpoint de correo/contraseña que usa la CLI (`tuist auth`).

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_EMAIL_AUTH_ENABLED` | Indica si se pueden usar el correo electrónico y la contraseña para iniciar sesión y registrarse. Establece en `0` para eliminar el formulario de correo/contraseña, el enlace de registro y el flujo de restablecimiento de contraseña de la página de inicio de sesión y cerrar los endpoints del servidor correspondientes | No | `1` | `0` |

#### Desactivar un proveedor de identidad configurado {#disabling-a-configured-identity-provider}

Por defecto, un proveedor aparece como opción de inicio de sesión siempre que esté configurado. Para mantener un proveedor configurado (sus credenciales permanecen establecidas) mientras lo eliminas de las páginas de inicio de sesión y registro, establece el interruptor correspondiente en `0`. Para GitHub, Google y Apple, esto también cierra la devolución de llamada de inicio de sesión, por lo que el método queda completamente inhabilitado.

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_AUTH_ENABLED` | Indica si se puede usar GitHub para iniciar sesión (consulta la sección [GitHub](#github) para saber por qué la App comparte sus credenciales con el inicio de sesión) | No | `1` | `0` |
| `TUIST_GOOGLE_AUTH_ENABLED` | Indica si se puede usar Google para iniciar sesión | No | `1` | `0` |
| `TUIST_OKTA_AUTH_ENABLED` | Indica si el proveedor de Okta configurado aparece como opción de inicio de sesión | No | `1` | `0` |
| `TUIST_APPLE_AUTH_ENABLED` | Indica si se puede usar Apple para iniciar sesión | No | `1` | `0` |

#### GitHub {#github}

Recomendamos autenticarse mediante una [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps), pero también puedes usar la [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app). Asegúrate de incluir todas las variables de entorno esenciales especificadas por GitHub en el entorno del servidor. La ausencia de variables hará que Tuist ignore la autenticación de GitHub. Para configurar correctamente la app de GitHub:
- En la configuración general de la app de GitHub:
    - Copia el `Client ID` y establécelo como `TUIST_GITHUB_APP_CLIENT_ID`
    - Crea y copia un nuevo `client secret` y establécelo como `TUIST_GITHUB_APP_CLIENT_SECRET`
    - Establece la `Callback URL` como `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` también puede ser la dirección IP de tu servidor.
- Se requieren los siguientes permisos:
  - Repositorios:
    - Pull requests: Lectura y escritura
  - Cuentas:
    - Direcciones de correo electrónico: Solo lectura

En la sección `Account permissions` de `Permissions and events`, establece el permiso `Email addresses` en `Read-only`.

A continuación, deberás exponer las siguientes variables de entorno en el entorno donde se ejecuta el servidor de Tuist:

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | El ID de cliente de la aplicación de GitHub | Sí | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | El secreto de cliente de la aplicación | Sí | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_AUTH_ENABLED` | Indica si se puede usar GitHub para iniciar sesión. La GitHub App que configures para integraciones de plataforma (comentarios de PR, etc.) comparte sus credenciales de cliente con el inicio de sesión, por lo que aparece como opción de inicio de sesión. Establece en `0` para mantener la App mientras eliminas GitHub de la página de inicio de sesión | No | `1` | `0` |

#### Google {#google}

Puedes configurar la autenticación con Google mediante [OAuth 2](https://developers.google.com/identity/protocols/oauth2). Para ello, tendrás que crear una nueva credencial de tipo ID de cliente OAuth. Al crear las credenciales, selecciona "Aplicación web" como tipo de aplicación, asígnale el nombre `Tuist` y establece el URI de redirección en `{base_url}/users/auth/google/callback`, donde `base_url` es la URL en la que se ejecuta tu servicio alojado. Una vez creada la app, copia el ID de cliente y el secreto y establécelos como variables de entorno `GOOGLE_CLIENT_ID` y `GOOGLE_CLIENT_SECRET` respectivamente.

> [!NOTE]
> **Ámbitos de la pantalla de consentimiento**
>
> Es posible que necesites crear una pantalla de consentimiento. Cuando lo hagas, asegúrate de añadir los ámbitos `userinfo.email` y `openid` y marcar la app como interna.


#### Okta {#okta}

Puedes habilitar la autenticación con Okta mediante el protocolo [OAuth 2.0](https://oauth.net/2/). Tendrás que [crear una app](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta) en Okta siguiendo <.localized_link href="/guides/integrations/authentication/sso#okta">estas instrucciones</.localized_link>.

Deberás establecer las siguientes variables de entorno una vez que obtengas el ID de cliente y el secreto durante la configuración de la aplicación de Okta:

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | El ID de cliente para autenticarse contra Okta. El número debe ser el ID de tu organización | Sí | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | El secreto de cliente para autenticarse contra Okta | Sí | | |

El número `1` debe reemplazarse por el ID de tu organización. Normalmente será 1, pero compruébalo en tu base de datos.

### Configuración del entorno de almacenamiento {#storage-environment-configuration}

 Tuist necesita almacenamiento para guardar los artefactos subidos a través de la API. Es **fundamental configurar una de las soluciones de almacenamiento admitidas** para que Tuist funcione correctamente.

Establece `TUIST_OBJECT_STORAGE_PROVIDER` para elegir el backend de artefactos del servidor:

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_OBJECT_STORAGE_PROVIDER` | Backend de almacenamiento de artefactos del servidor. Usa `s3` para almacenamiento compatible con S3 o `azure_blob` para Azure Blob Storage | No | `s3` | `azure_blob` |

#### Almacenamientos compatibles con S3 {#s3compliant-storages}

Puedes usar cualquier proveedor de almacenamiento compatible con S3 para almacenar artefactos. Las siguientes variables de entorno son necesarias para autenticar y configurar la integración con el proveedor de almacenamiento:

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` o `AWS_ACCESS_KEY_ID` | El ID de clave de acceso para autenticarse contra el proveedor de almacenamiento | Sí | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` o `AWS_SECRET_ACCESS_KEY` | La clave secreta de acceso para autenticarse contra el proveedor de almacenamiento | Sí | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` o `AWS_REGION` | La región donde se encuentra el bucket | No | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` o `AWS_ENDPOINT` | El endpoint del proveedor de almacenamiento | Sí | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | El nombre del bucket donde se almacenarán los artefactos | Sí | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | Certificado de CA codificado en PEM para verificar las conexiones HTTPS de S3. Útil para entornos aislados con certificados autofirmados o autoridades de certificación internas. | No | Paquete de CA del sistema | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | El tiempo de espera (en milisegundos) para establecer una conexión con el proveedor de almacenamiento | No | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | El tiempo de espera (en milisegundos) para recibir datos del proveedor de almacenamiento | No | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | El tiempo de espera (en milisegundos) para el pool de conexiones al proveedor de almacenamiento. Usa `infinity` para no tener tiempo de espera | No | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | El tiempo máximo de inactividad (en milisegundos) para las conexiones en el pool. Usa `infinity` para mantener las conexiones activas indefinidamente | No | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | El número máximo de conexiones por pool | No | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | El número de pools de conexión a usar | No | Número de planificadores del sistema | `4` |
| `TUIST_S3_PROTOCOL` | El protocolo a usar al conectarse al proveedor de almacenamiento (`http1` o `http2`) | No | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | Si la URL debe construirse con el nombre del bucket como subdominio (host virtual) | No | `false` | `1` |

> [!NOTE]
> **Autenticación de AWS con token de identidad web desde variables de entorno**
>
> Si tu proveedor de almacenamiento es AWS y deseas autenticarte usando un token de identidad web, puedes establecer la variable de entorno `TUIST_S3_AUTHENTICATION_METHOD` a `aws_web_identity_token_from_env_vars`, y Tuist usará ese método utilizando las variables de entorno convencionales de AWS.


#### Google Cloud Storage {#google-cloud-storage}
Para Google Cloud Storage, sigue [esta documentación](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) para obtener el par `AWS_ACCESS_KEY_ID` y `AWS_SECRET_ACCESS_KEY`. El `AWS_ENDPOINT` debe establecerse a `https://storage.googleapis.com`. Las demás variables de entorno son las mismas que para cualquier otro almacenamiento compatible con S3.

#### Azure Blob Storage {#azure-blob-storage}

Para Azure Blob Storage, establece `TUIST_OBJECT_STORAGE_PROVIDER=azure_blob` y configura las credenciales de la cuenta de almacenamiento de Azure:

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_AZURE_STORAGE_ACCOUNT_NAME` | Nombre de la cuenta de Azure Storage | Sí | | `tuiststorage` |
| `TUIST_AZURE_STORAGE_ACCOUNT_KEY` | Clave de acceso de la cuenta de almacenamiento usada para firmar solicitudes REST de Azure Blob y URLs SAS | Sí | | `******` |
| `TUIST_AZURE_BLOB_CONTAINER_NAME` | Contenedor donde se almacenan los artefactos del servidor | Sí | | `tuist-artifacts` |
| `TUIST_AZURE_BLOB_ENDPOINT` | Punto de conexión del servicio Blob. Omítelo para usar `https://<account>.blob.core.windows.net` | No | Derivado del nombre de la cuenta | `https://tuiststorage.blob.core.windows.net` |
| `TUIST_AZURE_BLOB_SERVICE_VERSION` | Versión de la API REST de Azure Blob usada para solicitudes firmadas y URLs SAS | No | `2020-12-06` | `2020-12-06` |

Al usar el chart de Helm, establece `server.storage.provider=azure_blob` y completa `server.azureBlob.*`. La configuración de nivel superior `objectStorage` del chart sigue siendo compatible con S3 porque las cargas de trabajo opcionales de caché y espejo de registro aún esperan almacenamiento compatible con S3. Si esas cargas de trabajo están deshabilitadas y el servidor usa Azure Blob, establece `objectStorage.mode=external` y deja vacíos el punto de conexión y las credenciales del almacenamiento de objetos externo para evitar desplegar el servicio MinIO embebido.

#### Retención de artefactos {#artifact-retention}

La limpieza de artefactos está deshabilitada por defecto en instancias autoalojadas. Cada tipo de artefacto admitido tiene su propia variable de entorno. Establece una variable a un número entero positivo de días para habilitar la limpieza para ese tipo de artefacto. Dejar una variable sin establecer o en blanco deshabilita la limpieza solo para su tipo de artefacto.

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

Con el chart de Helm, configura las mismas ventanas como un mapa:

```yaml
server:
  artifactRetentionDays:
    cacheArtifacts: 30
    appPreviews: 30
    buildArchives: 60
    runArtifacts: 30
    testAttachments: 30
    shardBundles: 14
```

Las seis claves son opcionales. Este ejemplo habilita cada tipo de artefacto admitido con una ventana de retención independiente. Omite una clave o deja su valor en blanco para mantener la limpieza deshabilitada para ese tipo de artefacto. Las ventanas de retención autoalojadas no tienen un máximo de 30 días. Los valores configurados que no son enteros positivos provocan que el servidor falle al iniciarse.

Reinicia el servidor después de cambiar una variable de retención. Cada lote de limpieza autoalojada en cola verifica la configuración actual antes de eliminar archivos, por lo que dejar una variable sin establecer o en blanco, o aumentar su ventana, también protege los archivos de trabajos pendientes después del reinicio.

| Variable de entorno | Archivos de artefactos eliminados del almacenamiento de objetos |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Caché de Xcode, caché de almacenamiento direccionable por contenido heredado, caché de módulos y archivos de caché de Gradle |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | Compilaciones e iconos de previsualización de apps |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | Archivos de compilación actuales y heredados |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | Todos los objetos almacenados bajo el prefijo de artefactos de una ejecución expirada, incluidos paquetes de resultados, registros de invocación y archivos de sesión |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | Archivos adjuntos de ejecuciones de tests |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | Paquetes de fragmentos de tests |

La limpieza programada elimina solo los blobs de artefactos. Conserva las filas correspondientes de PostgreSQL y ClickHouse, por lo que los metadatos de compilación, test, ejecución, previsualización y fragmentos pueden permanecer visibles en los paneles después de que expiren sus descargas. Esta configuración no cambia las reglas de retención de las tablas de ClickHouse.

### Configuración de correo electrónico {#email-configuration}

Tuist requiere funcionalidad de correo electrónico para la autenticación de usuarios y notificaciones transaccionales (por ejemplo, restablecimiento de contraseñas, notificaciones de cuenta). Actualmente, **solo se admite Mailgun** como proveedor de correo electrónico.

| Variable de entorno | Descripción | Requerida | Por defecto | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | La clave de API para autenticarse con Mailgun | Sí* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | El dominio desde el cual se enviarán los correos electrónicos | Sí* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | La dirección de correo electrónico que aparecerá en el campo "De" | Sí* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | Dirección de respuesta opcional para las respuestas de los usuarios | No | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | Omitir la confirmación por correo electrónico para nuevos registros de usuarios. Cuando está habilitado, los usuarios se confirman automáticamente y pueden iniciar sesión inmediatamente después del registro | No | `true` si el correo electrónico no está configurado, `false` si el correo electrónico está configurado | `true`, `false`, `1`, `0` |

\* Las variables de configuración de correo electrónico son requeridas solo si deseas enviar correos electrónicos. Si no están configuradas, la confirmación por correo electrónico se omite automáticamente

> [!NOTE]
> **Soporte de SMTP**
>
> El soporte genérico de SMTP no está disponible actualmente. Si necesitas soporte de SMTP para tu despliegue on-premise, ponte en contacto con [contact@tuist.dev](mailto:contact@tuist.dev) para comentar tus requisitos.


> [!NOTE]
> **Despliegues aislados de red**
>
> Para instalaciones on-premise sin acceso a internet o configuración de proveedor de correo electrónico, la confirmación por correo electrónico se omite automáticamente por defecto. Los usuarios pueden iniciar sesión inmediatamente después del registro. Si tienes el correo electrónico configurado pero aún deseas omitir la confirmación, establece `TUIST_SKIP_EMAIL_CONFIRMATION=true`. Para requerir la confirmación por correo electrónico cuando el correo esté configurado, establece `TUIST_SKIP_EMAIL_CONFIRMATION=false`.


### Configuración de la plataforma Git {#git-platform-configuration}

Tuist puede <.localized_link href="/guides/server/authentication">integrarse con plataformas Git</.localized_link> para ofrecer funcionalidades adicionales, como publicar comentarios automáticamente en tus pull requests.

#### GitHub {#platform-github}

Un servidor Tuist autoalojado no puede instalar la GitHub App que se ejecuta en `https://tuist.dev`. Las GitHub Apps están vinculadas al servidor que las registró, por lo que tu despliegue necesita su propia App en github.com.

##### Registro de la App {#platform-github-registering-the-app}

[Crea una GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) propiedad de tu organización de GitHub. Puedes reutilizar la App que creaste para la autenticación, a menos que hayas creado una OAuth App. Configúrala con lo siguiente, reemplazando `YOUR_APP_URL` con el valor de `TUIST_APP_URL`:

| Ajuste | Valor |
| --- | --- |
| URLs de callback | `YOUR_APP_URL/users/auth/github/callback` y `YOUR_APP_URL/integrations/github/authorize` |
| URL de configuración | `YOUR_APP_URL/integrations/github/setup` |
| Redirección al actualizar | Habilitado |
| URL del webhook | `YOUR_APP_URL/webhooks/github` |
| Secreto del webhook | Cualquier cadena aleatoria. La establecerás como `TUIST_GITHUB_APP_WEBHOOK_SECRET` |

Otorga los siguientes permisos de repositorio:

| Permiso | Acceso |
| --- | --- |
| Contenido | Solo lectura |
| Metadatos | Solo lectura |
| Issues | Lectura y escritura |
| Pull requests | Lectura y escritura |
| Checks | Lectura y escritura |

Otorga también el permiso de organización **Miembros: solo lectura**. Durante la configuración en github.com, Tuist verifica que la persona que conecta una instalación de organización sea un propietario activo de la organización de GitHub, no solo alguien con acceso a uno de sus repositorios.

Suscribe la App a los eventos `Check run`, `Pull request` y `Issue comment`.

Mantén deshabilitada la opción **Solicitar autorización de usuario (OAuth) durante la instalación** para que GitHub envíe a los instaladores a la URL de configuración. Tuist inicia un paso de autorización separado utilizando el callback adicional `/integrations/github/authorize` para verificar la propiedad de la instalación. Cuando la instalación comienza en GitHub, el instalador selecciona entonces una organización de Tuist; las instalaciones iniciadas en Tuist conservan su organización.

##### Configuración del servidor {#platform-github-configuring-the-server}

Establece las siguientes variables de entorno y luego reinicia el servidor:

| Variable de entorno | Descripción | Requerida | Predeterminado | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_NAME` | El slug de la App, que es el último componente de la ruta de su URL de página pública `https://github.com/apps/<slug>` | Sí | | `my-company-tuist` |
| `TUIST_GITHUB_APP_ID` | El ID numérico de la App, utilizado para verificar la propiedad de la instalación | Sí | | `123456` |
| `TUIST_GITHUB_APP_CLIENT_ID` | El ID de cliente de la aplicación de GitHub | Sí | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | El secreto de cliente de la aplicación | Sí | | `232f972951033b89799b0fd24566a04d83f44ccc` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | La clave privada codificada en base64 de la aplicación de GitHub. Se prefiere sobre `TUIST_GITHUB_APP_PRIVATE_KEY`, que es sensible a cómo tu plataforma maneja los saltos de línea | Sí | | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` |
| `TUIST_GITHUB_APP_WEBHOOK_SECRET` | El secreto del webhook configurado en la aplicación de GitHub | No | | `a4c1e0f2b8d6...` |

> [!IMPORTANT]
> **Configura todas las credenciales requeridas de la App**
>
> El botón **Instalar GitHub App** en la página de integraciones de la organización permanece deshabilitado hasta que se establezcan `TUIST_GITHUB_APP_NAME`, `TUIST_GITHUB_APP_CLIENT_ID`, `TUIST_GITHUB_APP_CLIENT_SECRET` y la clave privada. El `TUIST_GITHUB_APP_ID` numérico también es necesario para verificar la propiedad de la instalación. La URL de instalación incluye el slug de la App, por lo que la falta de `TUIST_GITHUB_APP_NAME` en particular genera un enlace al que GitHub responde con un 404.

Una vez que el servidor se reinicia, los administradores de la organización instalan la App y conectan los repositorios a los proyectos siguiendo la <.localized_link href="/guides/integrations/gitforge/github">guía de integración de GitHub</.localized_link>.

##### La autenticación OIDC depende de esto {#platform-github-oidc}

La <.localized_link href="/guides/server/authentication#oidc-tokens">autenticación OIDC</.localized_link> resuelve la reclamación del repositorio en el token de CI frente a los repositorios conectados a tus proyectos, y una conexión solo puede crearse a través de una GitHub App instalada. Completa la configuración anterior antes de que tus flujos de trabajo de CI ejecuten `tuist auth login` sin un token.

Tu servidor Tuist también necesita acceso saliente al emisor OIDC de tu proveedor de CI para obtener sus claves de firma:

| Proveedor de CI | Host |
| --- | --- |
| GitHub Actions | `token.actions.githubusercontent.com` |
| CircleCI | `oidc.circleci.com` |
| Bitrise | `token.builds.bitrise.io` |

##### GitHub Enterprise Server {#platform-github-enterprise-server}

Las variables de entorno anteriores solo configuran la App de github.com de Tuist. Para integrar Tuist con una instancia de GitHub Enterprise Server (GHES) en su lugar, los administradores de la organización cambian a la pestaña **Servidor empresarial** en la página de integraciones e introducen la URL base de GHES; Tuist los guía a través del [flujo de manifiesto de App](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) de GitHub para registrar una nueva App de Tuist en su instancia de GHES. Las credenciales de la nueva App se almacenan cifradas por instalación; no se necesitan variables de entorno `TUIST_GITHUB_APP_*` adicionales.

#### Origin {#platform-origin}

Un servidor Tuist autoalojado necesita su propia app de Origin, configurada con las URLs y la clave de firma de tu despliegue. Registra una app separada para cada entorno de Tuist para que las instalaciones y las credenciales permanezcan independientes.

##### Registro de la App {#platform-origin-registering-the-app}

1. Genera un par de claves de firma Ed25519 usando OpenSSL con soporte para Ed25519:

   ```sh
   umask 077
   openssl genpkey -algorithm ED25519 -out origin-app-private.pem
   openssl pkey -in origin-app-private.pem -pubout -out origin-app-public.pem
   ```

2. Crea una app en la [configuración de apps de Origin](https://cursor.com/codebase/settings/apps). Registra el contenido de `origin-app-public.pem` como su clave pública de firma. Mantén `origin-app-private.pem` en secreto; se lo proporcionarás al servidor Tuist, no lo subirás a Cursor.
3. Configura los siguientes ajustes, reemplazando `YOUR_APP_URL` con la URL base HTTPS de tu despliegue de Tuist:

   | Ajuste | Valor |
   | --- | --- |
   | URL de la página principal | `YOUR_APP_URL` |
   | URI de redirección | `YOUR_APP_URL/integrations/origin/setup` |
   | URL del webhook | `YOUR_APP_URL/webhooks/origin` |

4. Copia el ID de la App registrada, que comienza con `app_`.

Tuist solicita los siguientes permisos durante la instalación:

| Ámbito | Utilizado para |
| --- | --- |
| `repository:pull_requests:read` | Encontrar pull requests y su commit head actual. |
| `repository:pull_requests:reviews:write` | Leer, publicar y actualizar comentarios de informes. Origin incluye el permiso correspondiente de lectura de revisiones. |
| `repository:metadata:read` | Descubrir repositorios y leer sus ramas predeterminadas. Concedido automáticamente por Origin. |

Deja sin seleccionar los eventos opcionales de webhook del repositorio. Las notificaciones del ciclo de vida de la instalación son suficientes; no se requieren acceso al código fuente, permisos de merge ni permisos de check-run.

##### Configuración del servidor {#platform-origin-configuring-the-server}

Establece las siguientes variables de entorno y luego reinicia el servidor:

| Variable de entorno | Descripción | Requerido | Predeterminado | Ejemplo |
| --- | --- | --- | --- | --- |
| `TUIST_ORIGIN_APP_ID` | El ID de la App copiado desde la configuración de apps de Origin. | Sí | | `app_...` |
| `TUIST_ORIGIN_APP_PRIVATE_KEY` | El contenido completo de `origin-app-private.pem`, incluidas las líneas `BEGIN PRIVATE KEY` y `END PRIVATE KEY` y todos los saltos de línea. | Sí | | `-----BEGIN PRIVATE KEY-----...` |

Almacena la clave privada en el gestor de secretos de tu despliegue. Conserva su formato PEM multilínea; este ajuste no acepta un reemplazo codificado en base64. Nunca confirmes la clave en el control de versiones ni la expongas en los registros. Ambas variables deben pertenecer a la misma app registrada.

Tu servidor Tuist necesita acceso HTTPS saliente a `api.cursor.com`. Cursor debe poder entregar solicitudes a la URL del webhook y los administradores deben poder volver a la URI de redirección en su navegador. Ambas URLs registradas deben coincidir con la URL base HTTPS de tu despliegue.

##### Instalación de la App {#platform-origin-installing-the-app}

Una vez que el servidor se reinicie, un administrador abre **Ajustes → Integraciones**, elige **Conectar** bajo Origin y aprueba el acceso de la app a la cuenta y los repositorios de Origin apropiados. La organización de Tuist se mantiene durante todo este flujo. Las instalaciones iniciadas directamente desde Origin, en cambio, solicitan al administrador que inicie sesión y seleccione la organización de Tuist para conectar. Luego eligen **Agregar nueva conexión de proyecto** para vincular un proyecto de Tuist a un repositorio nativo.

Sigue la <.localized_link href="/guides/integrations/gitforge/origin">guía de integración de Origin</.localized_link> para las conexiones de proyectos y los requisitos de carga de resultados. Instalar la app no inicia flujos de trabajo de compilación o pruebas; esos flujos continúan reportando resultados a tu servidor Tuist.

## Pruebas locales {#testing-locally}

Proporcionamos una configuración completa de Docker Compose que incluye todas las dependencias necesarias para probar el servidor Tuist en tu máquina local antes de desplegarlo en tu infraestructura:

- PostgreSQL 15
- ClickHouse 26.5 para análisis
- ClickHouse Keeper para coordinación
- MinIO para almacenamiento compatible con S3
- Kura para pruebas locales de caché autoalojada
- pgweb para administración de bases de datos

> [!CAUTION]
> **Licencia requerida**
>
> Se requiere legalmente una variable de entorno `TUIST_LICENSE` válida para ejecutar el servidor Tuist, incluidas las instancias de desarrollo local. Si necesitas una licencia, ponte en contacto con [contact@tuist.dev](mailto:contact@tuist.dev).


**Inicio rápido:**

1. Descarga los archivos de configuración:
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-level.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-log-ttl.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. Configura las variables de entorno:
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE, TUIST_SECRET_KEY_BASE, and authentication credentials
   ```

   El servicio ClickHouse incluido acepta estos controles operativos de registro opcionales:

   | Variable de entorno | Descripción | Predeterminado | Ejemplo |
   | --- | --- | --- | --- |
   | `CLICKHOUSE_SYSTEM_LOG_TTL_DAYS` | Ventana de retención, en días, para las tablas de registro `system.*` de ClickHouse como `text_log`, `query_log`, `trace_log`, `metric_log` y `part_log` | `14` | `7` |
   | `CLICKHOUSE_TEXT_LOG_LEVEL` | Nivel del registrador del servidor ClickHouse y de `system.text_log` | `information` | `warning` |
   | `CLICKHOUSE_SUPERSEDED_LOG_TABLES` | Qué hacer con las tablas `<name>_N` que ClickHouse deja atrás cuando sustituye una tabla de registro del sistema. `ignore` las mantiene, `delete` las elimina | `ignore` | `delete` |

3. Inicia todos los servicios:
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

   En Apple Silicon, Docker Desktop descarga automáticamente las variantes `linux/arm64` de las imágenes de Tuist y sus dependencias. Para forzar la emulación amd64 para depuración, ejecuta Compose con `DOCKER_DEFAULT_PLATFORM=linux/amd64`.

   El archivo compose incluido utiliza volúmenes Docker con nombre para los datos persistentes. Si los reemplazas con montajes bind del host, crea primero los directorios del host y hazlos escribibles por los usuarios del contenedor, especialmente los directorios de datos de ClickHouse y ClickHouse Keeper.

4. Accede al servidor en http://localhost:8080

**Endpoints de servicio:**
- Servidor Tuist: http://localhost:8080
- Caché Kura (HTTP + REAPI gRPC en un solo puerto): http://localhost:4000
- Consola MinIO: http://localhost:9003 (credenciales: `tuist` / `tuist_dev_password`)
- API MinIO: http://localhost:9002
- pgweb (UI de PostgreSQL): http://localhost:8081
- Métricas Prometheus: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**Comandos comunes:**

Comprueba el estado del servicio:
```bash
docker compose ps
# or: podman compose ps
```

Ver registros:
```bash
docker compose logs -f tuist
```

Detener servicios:
```bash
docker compose down
```

Restablecer todo (elimina todos los datos):
```bash
docker compose down -v
```

**Archivos de configuración:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - Configuración completa de Docker Compose
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - Configuración de ClickHouse
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - Configuración de ClickHouse Keeper
- [.env.example](/server/self-host/.env.example) - Archivo de ejemplo de variables de entorno

## Kubernetes con Helm {#kubernetes-with-helm}

Tuist proporciona un chart oficial de Helm para desplegar en Kubernetes. El chart empaqueta el servidor Tuist y el servicio de caché, junto con dependencias de infraestructura incrustadas que puedes intercambiar por proveedores externos según sea necesario.

### Instalación del chart {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

Para fijar una versión específica del chart:

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### Licencia {#helm-license}

El valor `server.license.key` acepta tanto la clave de licencia estándar como, para instalaciones aisladas de red, el certificado de licencia codificado en Base64; el servidor detecta automáticamente cuál es.

Pasar la licencia con `--set` funciona para una instalación rápida. Si mantienes tus valores en control de versiones, almacena la licencia en un Secret de Kubernetes que gestiones fuera de Helm, por ejemplo con Vault, Sealed Secrets o SOPS, y apunta el chart hacia él:

```yaml
# values.yaml
server:
  license:
    existingSecret: tuist-license
    existingSecretKeys:
      key: TUIST_LICENSE
      certificateBase64: ""
```

La entrada bajo `existingSecretKeys.key` nombra el campo en tu Secret que contiene el valor de la licencia, que puede ser la clave de licencia o, para instalaciones aisladas de red, el certificado de licencia codificado en Base64. Cada entrada bajo `existingSecretKeys` tiene como predeterminado el nombre de clave propio del chart, así que establece las entradas que tu Secret no contiene como una cadena vacía, como se hace arriba con `certificateBase64`. De lo contrario, los pods referencian claves que no existen y fallan al iniciarse. Crea el Secret en el namespace de la release antes de instalar o actualizar el chart.

Configura la licencia a través de una única fuente: `server.license.key` o `server.license.existingSecret`. El chart falla al renderizarse cuando ninguna está establecida o cuando se combinan fuentes. Una licencia pasada a través de `server.extraEnv` no cuenta como fuente, así que usa `existingSecret` en su lugar.

### Dependencias de infraestructura {#helm-infrastructure-dependencies}

El chart gestiona tres dependencias de infraestructura: `postgresql`, `clickhouse` y `objectStorage`. Cada una tiene como modo predeterminado **incrustado**, lo que significa que el chart las despliega dentro del clúster. Para apuntar a tus propias instancias externas en su lugar, establece el `mode` de la dependencia a `external` y completa los detalles de conexión en tu `values.yaml`. Por ejemplo, para usar una base de datos PostgreSQL externa:

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    host: your-db-host
    port: 5432
    database: tuist
    username: tuist
    password: your-password
```

Si gestionas las credenciales de PostgreSQL fuera de Helm, apunta el chart a un Secret de Kubernetes existente en su lugar:

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    port: 5432
    database: tuist
    existingSecret: tuist-postgresql
    existingSecretKeys:
      host: host
      username: username
      password: password
```

El chart lee el host, el nombre de usuario y la contraseña del Secret y compone `DATABASE_URL` mediante la sustitución de variables de entorno de Kubernetes, por lo que la contraseña no se representa en el manifiesto de Helm. El valor de la contraseña del Secret debe ser seguro para URLs porque se interpola en una URL de base de datos.

El mismo patrón se aplica a `clickhouse` y `objectStorage`. Consulta el bloque `external` bajo cada sección en el `values.yaml` del chart para ver el conjunto completo de campos configurables.

### Programación compartida y etiquetas {#helm-shared-scheduling-and-labels}

El chart expone un pequeño conjunto de configuraciones compartidas para pods bajo `global` para que los operadores puedan adaptar el despliegue a su clúster sin repetir los mismos valores para cada carga de trabajo:

```yaml
global:
  podLabels:
    environment: production
  imagePullSecrets:
    - name: ghcr-pull-secret
  nodeSelector:
    nodepool: apps
  tolerations:
    - key: dedicated
      operator: Equal
      value: apps
      effect: NoSchedule
```

Usa estas configuraciones cuando necesites:

- añadir etiquetas específicas del clúster a cada pod
- extraer imágenes replicadas desde un registro privado
- apuntar a un pool de nodos dedicado
- permitir pods en nodos con taints reservados para cargas de trabajo de Tuist

### Identidad de carga de trabajo y cuentas de servicio {#helm-workload-identity}

El chart define el alcance de las cuentas de servicio por carga de trabajo de aplicación para que puedas conceder identidad solo donde sea necesario:

- `server.serviceAccount` se aplica al despliegue del servidor de Tuist y al job de migración
- `cache.serviceAccount` se aplica al despliegue de la caché

Por ejemplo, cuando la caché usa un bucket S3 externo en EKS, puedes habilitar IRSA para la carga de trabajo de la caché sin adjuntar también el mismo rol IAM a las bases de datos incrustadas:

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### Anulaciones de compatibilidad {#helm-compatibility-overrides}

El chart mantiene las personalizaciones específicas de almacenamiento y malla como opcionales para que los valores predeterminados sigan siendo portables:

```yaml
cache:
  podSecurityContext:
    fsGroup: 990

clickhouse:
  embedded:
    service:
      nativePort: 9100
    systemLogs:
      ttlDays: 7
      supersededTables: delete
      level: warning
```

Usa estas anulaciones solo cuando tu clúster las requiera:

- `cache.podSecurityContext` está vacío por defecto. Establece `fsGroup` si tu clase de almacenamiento o driver CSI necesita propiedad de grupo compartida en volúmenes montados.
- `clickhouse.embedded.service.nativePort` tiene como valor predeterminado el puerto nativo estándar `9000` de ClickHouse y puede cambiarse cuando una malla de servicios o una reserva de plataforma entra en conflicto con ese puerto.
- `clickhouse.embedded.systemLogs.ttlDays` está vacío por defecto, lo que deja la retención ilimitada de ClickHouse en las tablas de logs internas incrustadas como `system.text_log`, `system.query_log`, `system.trace_log`, `system.metric_log` y `system.part_log`. Establecerlo sobrescribe esas tablas una vez, así que adóptalo junto con `supersededTables: delete` — consulta <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">limitar la retención de logs operativos</.localized_link>.
- `clickhouse.embedded.systemLogs.level` tiene como valor predeterminado `information` para el logger del servidor ClickHouse incrustado y `system.text_log`. A diferencia de `ttlDays`, no forma parte de ninguna definición de tabla, por lo que cambiarlo nunca sobrescribe una tabla.
- `clickhouse.embedded.systemLogs.supersededTables` tiene como valor predeterminado `ignore` y decide qué ocurre con las tablas `<name>_N` que ClickHouse deja atrás cuando sobrescribe una tabla de log del sistema. Establécelo en `delete` para eliminarlas en cada `helm upgrade`.
- Los cambios en `ttlDays` y `level` llegan al pod de ClickHouse la próxima vez que se reinicie, ya que ambos son montajes `subPath` y el chart no realiza un rolling update del StatefulSet cuando cambia su ConfigMap.

### Observabilidad {#helm-observability}

El chart incluye un stack de observabilidad opcional (OpenTelemetry Collector, Prometheus, Grafana, Loki y Tempo). Está **deshabilitado por defecto**. Para habilitarlo en tu `values.yaml`:

```yaml
# values.yaml
observability:
  enabled: true
```

Cuando está habilitado, Grafana está disponible con desgloses preconfigurados de Logs, Traces y Metrics. Para observabilidad externa, mantén esto deshabilitado y configura los endpoints a través de `server.extraEnv`:

```yaml
# values.yaml
server:
  extraEnv:
    - name: TUIST_OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://your-otel-collector:4317"
    - name: TUIST_LOKI_URL
      value: "http://your-loki:3100"
```

### Referencia de valores {#helm-values-reference}

Para la lista completa de valores configurables, consulta el [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) del chart.

## Despliegue {#deployment}

La imagen oficial de Docker de Tuist está disponible en:
```
ghcr.io/tuist/tuist
```

La imagen publicada incluye procesamiento de compilación Linux incrustado para archivos `.xcactivitylog`, por lo que los despliegues autoalojados pueden procesar compilaciones sin ejecutar ningún servicio adicional: el job Oban `ProcessBuildWorker` se ejecuta en proceso en cada pod del servidor. Si quieres descargar el procesamiento de compilaciones a un conjunto de réplicas dedicado (por ejemplo, para escalar el throughput de análisis independientemente de la capa web), establece `processor.enabled: true` en el chart de Helm: el chart despliega la misma imagen como consumidor exclusivo de cola (`TUIST_PROCESSOR_MODE=true`). Consulta [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) para ver el conjunto completo de parámetros.

> [!NOTE]
> El análisis de `.xcresult` depende de `xcresulttool` de Xcode, por lo que solo puede ejecutarse en macOS. La CLI gestiona esto de forma transparente para despliegues autoalojados: `tuist test` tiene como modo de procesamiento predeterminado **local** contra cualquier servidor que no sea `tuist.dev`, analizando el xcresult en la máquina del desarrollador (que ya tiene Xcode para la propia compilación) y subiendo los resultados estructurados. Los resultados de los tests se ingieren sin ninguna infraestructura adicional.

### Extracción de la imagen Docker {#pulling-the-docker-image}

Puedes recuperar la imagen ejecutando el siguiente comando:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

La imagen se publica tanto para `linux/amd64` como para `linux/arm64`, por lo que Docker selecciona automáticamente la arquitectura Linux nativa para el host.

O extrae una versión específica:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Despliegue de la imagen Docker {#deploying-the-docker-image}

El proceso de despliegue de la imagen Docker variará según el proveedor de nube elegido y el enfoque de despliegue continuo de tu organización. Dado que la mayoría de las soluciones y herramientas en la nube, como [Kubernetes](https://kubernetes.io/), utilizan imágenes Docker como unidades fundamentales, los ejemplos de esta sección deberían alinearse bien con tu configuración existente.

> [!WARNING]
> Si tu pipeline de despliegue necesita validar que el servidor está activo y funcionando, puedes enviar una petición HTTP `GET` a `/ready` y verificar un código de estado `200` en la respuesta.


#### Fly {#fly}

Para desplegar la app en [Fly](https://fly.io/), necesitarás un archivo de configuración `fly.toml`. Considera generarlo dinámicamente dentro de tu pipeline de Despliegue Continuo (CD). A continuación tienes un ejemplo de referencia para tu uso:

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

Luego puedes ejecutar `fly launch --local-only --no-deploy` para lanzar la app. En despliegues posteriores, en lugar de ejecutar `fly launch --local-only`, tendrás que ejecutar `fly deploy --local-only`. Fly.io no permite extraer imágenes Docker privadas, por eso necesitamos usar la bandera `--local-only`.


## Métricas de Prometheus {#prometheus-metrics}

Tuist expone métricas de Prometheus en `/metrics` para ayudarte a monitorizar tu instancia autoalojada. Estas métricas incluyen:

### Métricas del cliente HTTP Finch {#finch-metrics}

Tuist utiliza [Finch](https://github.com/sneako/finch) como su cliente HTTP y expone métricas detalladas sobre las peticiones HTTP:

#### Métricas de peticiones
- `tuist_prom_ex_finch_request_count_total` - Número total de peticiones de Finch (contador)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - Duración de las peticiones HTTP (histograma)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - Intervalos: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Número total de excepciones en peticiones de Finch (contador)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### Métricas de la cola del pool de conexiones
- `tuist_prom_ex_finch_queue_duration_milliseconds` - Tiempo de espera en la cola del pool de conexiones (histograma)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Intervalos: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - Tiempo que la conexión permaneció inactiva antes de ser utilizada (histograma)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Intervalos: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Número total de excepciones en la cola de Finch (contador)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### Métricas de conexión
- `tuist_prom_ex_finch_connect_duration_milliseconds` - Tiempo empleado en establecer una conexión (histograma)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`, `error`
  - Intervalos: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - Número total de intentos de conexión (contador)
  - Etiquetas: `finch_name`, `scheme`, `host`, `port`

#### Métricas de envío
- `tuist_prom_ex_finch_send_duration_milliseconds` - Tiempo empleado en enviar la petición (histograma)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Intervalos: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - Tiempo que la conexión permaneció inactiva antes del envío (histograma)
  - Etiquetas: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Intervalos: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

Todas las métricas de histograma proporcionan variantes `_bucket`, `_sum` y `_count` para un análisis detallado.

### Otras métricas

Además de las métricas de Finch, Tuist expone métricas para:
- Rendimiento de la máquina virtual BEAM
- Métricas personalizadas de lógica de negocio (almacenamiento, cuentas, proyectos, etc.)
- Rendimiento de la base de datos (al usar infraestructura alojada por Tuist)

## Operaciones {#operations}

Tuist ofrece un conjunto de utilidades bajo `/ops/` que puedes usar para gestionar tu instancia.

> [!WARNING]
> **Autorización**
>
> Solo los usuarios confirmados cuyo dominio de correo electrónico coincida con `TUIST_OPERATOR_EMAIL_DOMAIN` (por defecto `tuist.dev`) pueden acceder a los endpoints de `/ops/`.


- **Errores (`/ops/errors`):** Puedes ver errores inesperados que han ocurrido en la aplicación. Esto es útil para depurar y entender qué ha fallado, y podríamos pedirte que compartas esta información con nosotros si tienes problemas.
- **Panel de control (`/ops/dashboard`):** Puedes ver un panel de control que ofrece información sobre el rendimiento y el estado de la aplicación (por ejemplo, consumo de memoria, procesos en ejecución, número de peticiones). Este panel puede ser muy útil para determinar si el hardware que estás usando es suficiente para manejar la carga.
