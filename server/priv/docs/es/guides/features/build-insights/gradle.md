---
{
  "title": "Análisis de compilaciones de Gradle",
  "titleTemplate": ":title · Análisis de compilaciones · Funcionalidades · Guías · Tuist",
  "description": "Sigue los tiempos de las tareas de Gradle y el comportamiento de la caché en el panel de control de Tuist."
}
---
# Análisis de compilaciones de Gradle {#gradle-build-insights}

El plugin de Gradle de Tuist puede enviar análisis de compilación a Tuist, lo que te da visibilidad sobre la ejecución de tareas y el rendimiento de la compilación.

## Configurar el comportamiento de carga {#configure-upload-behavior}

De forma predeterminada:
- Los análisis de compilación se cargan en segundo plano para las compilaciones locales.
- Los análisis de compilación se cargan en primer plano para las ejecuciones de CI para evitar perder telemetría en agentes de vida corta.

Puedes controlar este comportamiento usando `uploadInBackground` dentro de la extensión `tuist`:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## Referencia de configuración {#configuration-reference}

La opción `uploadInBackground` está disponible en el bloque de extensión `tuist` en `settings.gradle.kts`:

| Opción | Tipo | Predeterminado | Descripción |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null` (segundo plano localmente, primer plano en CI) | Si cargar los análisis de compilación en segundo plano para las compilaciones locales. |

Esta configuración no afecta a la configuración de caché remota en el bloque `buildCache`.

## Afirmación del actor del informe {#report-actor-claim}

Las solicitudes de informes de compilación y prueba incluyen la cabecera opcional `x-tuist-actor-id` solo cuando estableces explícitamente `TUIST_ACTOR_ID` como una etiqueta con alcance de organización o configuras `buildInsights.actorId` en tu configuración. No se envía ninguna etiqueta por defecto, y el plugin no detecta nombres de usuario del sistema operativo. La sobrescritura de entorno tiene prioridad. Establece cualquiera de las sobrescrituras a una cadena vacía para omitir el identificador informado; esto no elimina la identidad establecida por credenciales individuales. Las sobrescrituras inválidas omiten la afirmación en lugar de recurrir a un valor por defecto. Si un proxy personalizado rechaza cabeceras desconocidas, opta por no participar con `TUIST_ACTOR_ID=""`.

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

Los identificadores de actor son de 1 a 128 bytes de ASCII imprimible sin espacios. Son visibles para cualquiera que pueda ver los informes del proyecto, incluidos los espectadores públicos cuando el proyecto es público, y se exportan con los informes. No incluyas secretos ni información personal que no quieras publicar. Una credencial individual verificada tiene prioridad en el panel; los identificadores enviados por los clientes son explícitamente **No verificados** en caso contrario. Nunca otorgan permisos ni se vinculan automáticamente a un usuario de Tuist. Los servidores antiguos ignoran la cabecera de atribución, y los nuevos servidores continúan aceptando clientes antiguos sin ella. Los nuevos informes con token compartido sin identificador muestran **Desconocido**, en lugar de la organización que publica; los informes históricos conservan su atribución anterior. Los listados de compilaciones y pruebas separan los filtros de usuarios verificados de los filtros de identificadores informados no verificados.

## Publicación de confianza de red {#network-trusted-publishing}

Las implementaciones autoalojadas pueden permitir explícitamente informes de compilación y prueba de Gradle desde su red de confianza sin credenciales de desarrollador. Un operador debe configurar `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` en la instancia y reiniciarla primero. Esto se aplica a todos los proyectos compatibles; no hay ninguna configuración en el panel. Consulta <.localized_link href="/guides/server/self-host/server#network-trusted-access">la guía de autoalojamiento</.localized_link>.

Configura el destino una vez en el repositorio:

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

La generación de informes de compilación y prueba no requiere el descubrimiento autenticado del punto final de caché. Deshabilita la caché a menos que la instancia habilite por separado el acceso a la caché de confianza de red o los desarrolladores proporcionen tokens. Los informes de prueba sin firma omiten las referencias a fragmentos y compilaciones existentes y no activan automatizaciones de cuarentena o inestabilidad. La búsqueda de cuarentena se omite cuando las credenciales están genuinamente ausentes; con credenciales válidas, se preserva el comportamiento autenticado existente. Si hay credenciales presentes, se siguen utilizando y las credenciales inválidas fallan en lugar de recurrir a la publicación sin credenciales. Cuando las credenciales están ausentes, el plugin descubre automáticamente si el servidor autoalojado permite la generación de informes sin credenciales. No se requiere ninguna bandera del cliente ni la configuración de `buildInsights`. Actualiza cada réplica del servidor a una versión compatible con el descubrimiento antes de actualizar los clientes sin credenciales. Los servidores antiguos sin descubrimiento, las instancias deshabilitadas y los errores de descubrimiento aún requieren autenticación; la publicación autenticada sigue siendo compatible. Un `TUIST_TOKEN` explícitamente vacío falla de forma segura en lugar de habilitar la publicación sin credenciales. Para trabajos de fork o Dependabot sin secretos, elimina esa variable en lugar de definirla como una cadena vacía.

El servidor asigna ID de informe sin credenciales. Repetir un envío puede crear un segundo informe; este modo no garantiza reintentos idempotentes ni correlación con informes de prueba autenticados. Dichos informes no pueden desencadenar comentarios en el VCS ni eventos automáticos de agentes de fallo. El acceso a la red es el límite de confianza de la publicación, no una prueba de la identidad del actor informado.

## Metadatos personalizados {#custom-metadata}

Adjunta etiquetas y datos clave-valor a las compilaciones de Gradle para comparar ejecuciones de diferentes equipos, hardware o flujos de trabajo. Las etiquetas están disponibles como filtros en el panel, y los valores aparecen en la página de detalles de cada compilación y en la interfaz de programación de aplicaciones y las herramientas del Protocolo de Contexto de Modelo.

Establece metadatos con variables de entorno:

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

También puedes configurar metadatos en `settings.gradle.kts`:

```kotlin
tuist {
    buildInsights {
        tag("nightly")
        tag("android")
        value("ticket", "TUIST-123")
        value("runner", "macos-14")
    }
}
```

Cuando el mismo valor se configura en ambos lugares, el valor en `settings.gradle.kts` tiene prioridad.

Las etiquetas deben contener solo letras, números, guiones y guiones bajos. Una compilación puede tener hasta 50 etiquetas, y cada etiqueta puede contener hasta 50 caracteres. Una compilación puede tener hasta 20 entradas clave-valor, cada clave puede contener hasta 50 caracteres y cada valor puede contener hasta 500 caracteres. Estos son los mismos límites del lado del servidor utilizados para los metadatos de compilación de Xcode. El plugin omite las etiquetas no válidas y las entradas de metadatos demasiado grandes o vacías antes de enviar el informe, por lo que una configuración no válida no puede impedir que el resto del informe de análisis de compilación se almacene. Usa metadatos clave-valor para valores que no cumplan la restricción de etiqueta.

Los metadatos personalizados son visibles para los miembros del proyecto en el panel y a través de la interfaz de programación de aplicaciones y las herramientas del Protocolo de Contexto de Modelo. No los uses para credenciales, tokens de acceso u otros datos sensibles. Tuist conserva los datos de compilación de Gradle, incluidos estos metadatos, durante 90 días. Consulta la <.localized_link href="/guides/server/data-retention">política de retención de datos</.localized_link> para más detalles.
