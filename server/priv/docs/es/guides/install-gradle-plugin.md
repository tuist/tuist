---
{
  "title": "Instalar el plugin de Gradle",
  "titleTemplate": ":title · Guías · Tuist",
  "description": "Aprende a instalar y configurar el plugin de Gradle de Tuist en tu proyecto."
}
---
# Instalar el plugin de Gradle {#install-the-gradle-plugin}

Tuist ofrece un plugin de Gradle que se integra con tu proyecto de Gradle para habilitar funcionalidades como <.localized_link href="/guides/features/cache/gradle-cache">caché remota de compilación</.localized_link> y <.localized_link href="/guides/features/build-insights/gradle">análisis de compilaciones</.localized_link>. Esta guía te acompaña paso a paso en la instalación y configuración del plugin.

El plugin requiere Gradle 8.12.1 o una versión posterior.

## 1. Inicializar Tuist {#initialize-tuist}

Ejecuta el siguiente comando en la raíz de tu proyecto de Gradle:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

El comando te guiará por el proceso de autenticación, creación o selección de un proyecto de Tuist y generación de la configuración para tu proyecto de Gradle.

## 2. Aplicar el plugin {#apply-the-plugin}

Después de ejecutar `tuist init`, deberás añadir el plugin de Tuist a tu `settings.gradle.kts` según las instrucciones mostradas en la salida del comando:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. Autenticar a tu equipo y a la integración continua {#authenticate}

Aunque `tuist init` te autentica localmente, tus compañeros de equipo y los entornos de <.localized_link href="/guides/integrations/continuous-integration">integración continua</.localized_link> deberán autenticarse por separado.

Cada compañero debe ejecutar lo siguiente para acceder a las funcionalidades de Tuist en su máquina:

```bash
tuist auth login
```

Cuando uses un servidor de Tuist autoalojado o local, indica la misma URL base configurada en `tuist.toml`:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

Mantén consistente la escritura del nombre de host. Por ejemplo, un inicio de sesión guardado para `localhost` es distinto de uno guardado para `127.0.0.1`.

Para runners automatizados, sigue la <.localized_link href="/guides/integrations/continuous-integration#authentication">guía de autenticación de integración continua</.localized_link> para configurar la autenticación en tu entorno.

## Caché de configuración y proyectos aislados {#configuration-cache-and-isolated-projects}

El plugin admite la caché de configuración de Gradle y los [proyectos aislados](https://docs.gradle.org/current/userguide/isolated_projects.html). Mantén el plugin en `settings.gradle.kts`; no necesitas aplicarlo por separado a cada subproyecto.

Tuist no activa ninguna de estas funcionalidades automáticamente. Para habilitarlas, añade lo siguiente a `gradle.properties`:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

Tus scripts de compilación y otros plugins también deben admitir estas funcionalidades. Gradle informa de problemas de compatibilidad al almacenar la caché de configuración.

## Referencia de configuración {#configuration-reference}

Las siguientes opciones están disponibles en el bloque de extensión `tuist` dentro de `settings.gradle.kts`:

| Opción | Tipo | Predeterminado | Descripción |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (opcional) | El identificador del proyecto en formato `account/project`. Si no se establece, el plugin lo lee desde `tuist.toml`. |
| `url` | `String?` | `null` | La URL base del servidor de Tuist. Si no se establece, el valor predeterminado es `"https://tuist.dev"` o el definido en `tuist.toml`. |
| `uploadInBackground` | `Boolean?` | `null` | Indica si se deben subir los análisis de compilación y tests en segundo plano. Cuando es `null` (predeterminado), las subidas se ejecutan en segundo plano para compilaciones locales y en primer plano en los runners de integración continua. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` o `"enforce"`. Vuelve a ejecutar los casos de test que añade una compilación y marca aquellos que resulten inestables; consulta <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">pruebas de estrés para nuevos tests</.localized_link>. Desactivado cuando no está configurado. |

Para un servidor local que use una URL `http://`, permite el protocolo inseguro solo en esa configuración local:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

No habilites `allowInsecureProtocol` para servidores alojados u otros servidores `https://`.

> [!NOTE]
> **Tuist.toml**
>
> La forma recomendada de configurar `project` (y opcionalmente `url`) es mediante un archivo `tuist.toml` en la raíz de tu proyecto. De este modo, la configuración se comparte entre la interfaz de línea de comandos de Tuist y el plugin de Gradle. Si es necesario, aún puedes sobrescribir estos valores en `settings.gradle.kts`.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## Proxy HTTP {#http-proxy}

Si tu red enruta el tráfico saliente a través de un proxy HTTP, consulta la <.localized_link href="/guides/integrations/http-proxy">guía de proxy HTTP</.localized_link>.

## Siguientes pasos {#next-steps}

Una vez instalado y configurado el plugin, puedes habilitar:

- <.localized_link href="/guides/features/cache/gradle-cache">Caché remota de compilación</.localized_link> para compartir artefactos de compilación entre tu equipo y los runners de integración continua.
- <.localized_link href="/guides/features/build-insights/gradle">Análisis de compilaciones</.localized_link> para seguir los tiempos de las tareas y el comportamiento de la caché en el panel de Tuist.
- <.localized_link href="/guides/features/test-insights/gradle">Análisis de tests</.localized_link> para seguir el rendimiento de los tests y detectar tests inestables.
- <.localized_link href="/guides/features/test-insights/flaky-tests">Tests inestables</.localized_link> para detectar, rastrear y poner en cuarentena automáticamente los tests inestables.
