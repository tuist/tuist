---
{
  "title": "Gradle cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Gradle build cache artifacts across your team and CI with Tuist."
}
---
# Caché de Gradle {#gradle-cache}

Tuist proporciona un plugin de Gradle que se integra con [la caché de compilación integrada de Gradle](https://docs.gradle.org/current/userguide/build_cache.html) para compartir artefactos de compilación de forma remota. Cuando los resultados de una tarea ya están en caché, Gradle omite la ejecución y obtiene el resultado de la caché remota de Tuist, ahorrando tiempo de compilación para tu equipo y entornos de CI.

Una vez instalado el <.localized_link href="/guides/install-gradle-plugin">plugin de Gradle de Tuist</.localized_link>, también debes habilitar la caché de compilación de Gradle en tu archivo `gradle.properties`:

```properties
org.gradle.caching=true
```

Sin esto, Gradle no activa su subsistema de caché de compilación, incluso con una caché remota configurada, y todas las tareas se ejecutarán sin utilizar ni rellenar la caché. Una vez habilitada, Gradle utilizará Tuist como caché de compilación remota, descargando los resultados de las tareas almacenados en caché cuando haya aciertos y subiéndolos después de la ejecución de la tarea.

## Política de subida a la caché {#cache-upload-policy}

Por defecto, el plugin tanto descarga como sube artefactos a la caché remota. Puedes controlar las subidas con la opción `push` en el bloque `buildCache`:

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

Un patrón común es subir artefactos solo desde CI, donde las compilaciones son reproducibles, mientras se mantienen los entornos locales en modo de solo lectura:

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

Con esta configuración, las compilaciones locales se benefician de los artefactos en caché sin subirlos, mientras que las compilaciones de CI rellenan la caché para el resto del equipo.

## Integración continua {#continuous-integration}

Para entornos de CI, autenticarse utilizando uno de los métodos de la <.localized_link href="/guides/server/authentication#continuous-integration">Guía de autenticación</.localized_link>. Consulta la <.localized_link href="/guides/integrations/continuous-integration">Guía de integración continua</.localized_link> para ver ejemplos específicos de cada proveedor de CI.

### Desactivar la caché de compilación local {#disabling-the-local-build-cache}

Gradle mantiene tanto una caché de compilación local como una remota. La caché de compilación local almacena los resultados de las tareas en el disco bajo `~/.gradle/caches/build-cache-1`.

Cuando Tuist está configurado como la caché de compilación remota, se recomienda desactivar la caché de compilación local en CI. Esto evita almacenar artefactos redundantes en los ejecutores de CI y garantiza que las compilaciones siempre rellenen la caché remota con entradas nuevas para el resto del equipo.

Desactiva la caché de compilación local de Gradle en CI en tu `settings.gradle.kts`:

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

| Opción | Tipo | Predeterminado | Descripción |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | Indica si la caché de compilación remota está habilitada. |
| `push` | `Boolean` | `true` | Indica si se deben subir los resultados de las tareas a la caché remota. |
| `allowInsecureProtocol` | `Boolean` | `false` | Indica si se permiten conexiones HTTP inseguras. |
