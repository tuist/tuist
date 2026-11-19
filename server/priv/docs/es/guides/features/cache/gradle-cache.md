---
{
  "title": "Caché de Gradle",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Comparte artefactos de la caché de compilación de Gradle con tu equipo y CI mediante Tuist."
}
---
# Caché de Gradle {#gradle-cache}

Tuist ofrece un plugin de Gradle que se integra con [la caché de compilación integrada de Gradle](https://docs.gradle.org/current/userguide/build_cache.html) para compartir artefactos de compilación de forma remota. Cuando los resultados de una tarea ya están en caché, Gradle omite la ejecución y obtiene el resultado desde la caché remota de Tuist, ahorrando tiempo de compilación para todo tu equipo y en entornos de CI. Para conocer las diferencias entre las cachés de compilación local y remota de Gradle, las comprobaciones de actualización y la caché de configuración, consulta <.localized_link href="/references/concepts/build-cache#gradle">¿Qué es una caché de compilación?</.localized_link>. Para identificar qué parte de una compilación lenta elimina la caché y qué corregir primero en el proyecto, consulta [Compilaciones lentas](https://tuist.dev/solutions/slow-builds).

Una vez instalado el <.localized_link href="/guides/install-gradle-plugin">plugin de Tuist para Gradle</.localized_link>, también debes habilitar la caché de compilación de Gradle en tu archivo `gradle.properties`:

```properties
org.gradle.caching=true
```

Sin esto, Gradle no activa su subsistema de caché de compilación, incluso con una caché remota configurada, y todas las tareas se ejecutarán sin aprovechar ni rellenar la caché. Una vez habilitada, Gradle usará Tuist como caché de compilación remota, descargando los resultados de tareas almacenados en caché cuando haya aciertos y subiéndolos tras la ejecución de cada tarea.

## Política de subida a la caché {#cache-upload-policy}

De forma predeterminada, el plugin descarga y sube artefactos a la caché remota. Puedes controlar las subidas con la opción `push` dentro del bloque `buildCache`:

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

Un patrón habitual es subir artefactos solo desde CI, donde las compilaciones son reproducibles, mientras se mantienen los entornos locales en modo de solo lectura:

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

Con esta configuración, las compilaciones locales se benefician de los artefactos en caché sin subirlos, mientras que las compilaciones de CI rellenan la caché para el resto del equipo.

## Integración continua {#continuous-integration}

Para entornos de CI, autentícate usando uno de los métodos de la <.localized_link href="/guides/server/authentication#continuous-integration">guía de autenticación</.localized_link>. Consulta la <.localized_link href="/guides/integrations/continuous-integration">guía de integración continua</.localized_link> para ver ejemplos específicos de cada proveedor de CI.

### Desactivar la caché de compilación local {#disabling-the-local-build-cache}

Gradle mantiene tanto una caché de compilación local como una remota. La caché de compilación local almacena los resultados de las tareas en disco bajo `~/.gradle/caches/build-cache-1`.

Cuando Tuist está configurado como caché de compilación remota, se recomienda desactivar la caché de compilación local en CI. Esto evita almacenar artefactos redundantes en los runners de CI y garantiza que las compilaciones siempre rellenen la caché remota con entradas actualizadas para el resto del equipo.

Desactiva la caché de compilación local de Gradle en CI en tu archivo `settings.gradle.kts`:

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

Esto mantiene la caché de compilación local disponible para el desarrollo local mientras la desactiva en CI, donde la caché remota de Tuist gestiona el intercambio de artefactos.

## Referencia de configuración {#configuration-reference}

El bloque `buildCache` admite:

| Opción | Tipo | Valor predeterminado | Descripción |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | Indica si la caché de compilación remota está habilitada. |
| `push` | `Boolean` | `true` | Indica si se deben subir los resultados de las tareas a la caché remota. |
| `allowInsecureProtocol` | `Boolean` | `false` | Indica si se permiten conexiones HTTP inseguras. |
