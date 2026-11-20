---
{
  "title": "Instalar el plugin de Gradle",
  "titleTemplate": ":title · Guías · Tuist",
  "description": "Aprende a instalar y configurar el plugin de Gradle de Tuist en tu proyecto."
}
---
# Instala el plugin de Gradle {#install-the-gradle-plugin}

Tuist ofrece un plugin de Gradle que se integra con tu proyecto de Gradle para habilitar funcionalidades como <.localized_link href="/guides/features/cache/gradle-cache">caché remota de compilación</.localized_link> y <.localized_link href="/guides/features/build-insights/gradle">análisis de compilaciones</.localized_link>. Esta guía te acompaña en la instalación y configuración del plugin.

El plugin requiere Gradle 8.12.1 o posterior.

## 1. Inicializa Tuist {#initialize-tuist}

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

El comando te guiará para autenticarte, crear o seleccionar un proyecto de Tuist y generar la configuración para tu proyecto de Gradle.

## 2. Aplica el plugin {#apply-the-plugin}

Después de ejecutar `tuist init`, deberás añadir el plugin de Tuist a tu `settings.gradle.kts` según las instrucciones mostradas en la salida del comando:

<!-- @snippet: ./_gradle-plugin-block -->

## 3. Autentica a tu equipo y la integración continua {#authenticate}

Mientras que `tuist init` te autentica localmente, tus compañeros de equipo y los entornos de <.localized_link href="/guides/integrations/continuous-integration">integración continua</.localized_link> necesitarán autenticarse por separado.

Cada compañero de equipo debe ejecutar lo siguiente para acceder a las funcionalidades de Tuist en su máquina:

```bash
tuist auth login
```

Cuando uses un servidor de Tuist autoalojado o local, pasa la misma URL base configurada en `tuist.toml`:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

Mantén consistente la escritura del nombre de host. Por ejemplo, un inicio de sesión almacenado para `localhost` es distinto de uno almacenado para `127.0.0.1`.

Para los runners automatizados, sigue la <.localized_link href="/guides/server/authentication#continuous-integration">guía de autenticación de integración continua</.localized_link> para configurar la autenticación en tu entorno.

## Caché de configuración y Proyectos aislados {#configuration-cache-and-isolated-projects}

El plugin admite la caché de configuración de Gradle y los [Proyectos aislados](https://docs.gradle.org/current/userguide/isolated_projects.html). Mantén el plugin en `settings.gradle.kts`; no necesitas aplicarlo por separado a cada subproyecto.

Tuist no activa ninguna de estas funcionalidades automáticamente. Para habilitarlas, añade lo siguiente a `gradle.properties`:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

Tus scripts de compilación y otros plugins también deben admitir estas funcionalidades. Gradle informa problemas de compatibilidad al almacenar la caché de configuración.

## Publica vistas previas {#publish-previews}

Para módulos de aplicación Android, el plugin registra las tareas `tuistShare<Variant>`:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

La tarea compila y verifica un único APK firmado y luego lo publica usando tu autenticación de Tuist existente. Invocar la tarea es la forma de optar por esta funcionalidad: las tareas ordinarias de `assemble`, `build` y de tests no publican vistas previas. No se requiere ningún paso de subida desde la CLI. Consulta <.localized_link href="/guides/features/previews/gradle">vistas previas de Gradle</.localized_link> para conocer los requisitos, la reproducción desde caché y el comportamiento ante fallos.

## Referencia de configuración {#configuration-reference}

Las siguientes opciones están disponibles en el bloque de extensión `tuist` en `settings.gradle.kts`:

| Opción | Tipo | Valor predeterminado | Descripción |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (opcional) | El identificador del proyecto en formato `account/project`. Si no se establece, el plugin lo lee de `tuist.toml`. |
| `url` | `String?` | `null` | La URL base del servidor de Tuist. Si no se establece, toma como valor predeterminado `"https://tuist.dev"` o el valor definido en `tuist.toml`. |
| `uploadInBackground` | `Boolean?` | `null` | Indica si se deben subir los análisis de compilación y de tests en segundo plano. Cuando es `null` (valor predeterminado), las subidas se ejecutan en segundo plano para compilaciones locales y en primer plano en los runners de integración continua. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` o `"enforce"`. Vuelve a ejecutar los casos de test que una compilación añade y marca aquellos que resulten inestables; consulta <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">pruebas de estrés para nuevos tests</.localized_link>. Desactivado cuando no se establece. |
| `coverage.enabled` | `Boolean?` | `null` | Mide la cobertura de tests con JaCoCo y la sube con cada ejecución de tests. Desactivado cuando no se establece. La variable de entorno `TUIST_TEST_COVERAGE` tiene prioridad sobre este valor; consulta <.localized_link href="/guides/features/test-code-coverage/gradle">cobertura de código en Gradle</.localized_link>. |

Para un servidor local que use una URL `http://`, permite el protocolo inseguro solo en esa configuración local:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

No actives `allowInsecureProtocol` para servidores alojados u otros servidores `https://`.

> [!NOTE]
> **Tuist.toml**
>
> La forma recomendada de configurar `project` (y opcionalmente `url`) es mediante un archivo `tuist.toml` en la raíz de tu proyecto. De este modo, la configuración se comparte entre la interfaz de línea de comandos de Tuist y el plugin de Gradle. Aún puedes sobrescribir estos valores en `settings.gradle.kts` si es necesario.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## Proxy HTTP {#http-proxy}

Si tu red enruta el tráfico saliente a través de un proxy HTTP, consulta la <.localized_link href="/guides/integrations/http-proxy">guía de proxy HTTP</.localized_link>.

## Próximos pasos {#next-steps}

Una vez instalado y configurado el plugin, puedes activar:

- <.localized_link href="/guides/features/cache/gradle-cache">Caché remota de compilación</.localized_link> para compartir artefactos de compilación entre tu equipo y los runners de integración continua.
- <.localized_link href="/guides/features/build-insights/gradle">Análisis de compilaciones</.localized_link> para seguir los tiempos de las tareas y el comportamiento de la caché en el panel de Tuist.
- <.localized_link href="/guides/features/test-insights/gradle">Análisis de tests</.localized_link> para seguir el rendimiento de los tests y detectar tests inestables.
- <.localized_link href="/guides/features/test-insights/flaky-tests">Tests inestables</.localized_link> para detectar, seguir y poner en cuarentena automáticamente los tests inestables.
- <.localized_link href="/guides/features/test-code-coverage/gradle">Cobertura de código</.localized_link> para seguir la cobertura de tus tests por commit, proyecto y archivo.
