---
{
  "title": "Proyecto Gradle",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Conecta un proyecto Gradle a Tuist para obtener una caché de compilación remota compartida, análisis de compilaciones y tests en CI, seguimiento del tamaño del bundle y enlaces de previsualización."
}
---
# Proyecto Gradle {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

Sigue esta guía para conectar un proyecto Gradle existente a Tuist. El plugin de Gradle `dev.tuist` enlaza la caché de compilación local de Gradle con la caché remota de Tuist y sube los datos de compilación y tests al panel, sin cambiar ni un solo comando `./gradlew`.

Cada sección siguiente comienza explicando qué falta hoy y luego te guía por la funcionalidad que cubre esa carencia.

## Requisitos previos

- Un proyecto Gradle con un `settings.gradle.kts` (o `settings.gradle`).
- La <.localized_link href="/guides/install-tuist">interfaz de línea de comandos de Tuist</.localized_link>.

## Conectar el proyecto

Desde la raíz del proyecto Gradle, ejecuta `tuist init`. Elige **Integrar un proyecto Gradle**, autentícate en el navegador y selecciona la cuenta que debe ser propietaria del proyecto.

```bash
tuist init
```

Si lo estás ejecutando desde un agente de programación o un script, ejecuta primero `tuist auth login` (el flujo del navegador espera a que pulses Intro) y luego usa la forma no interactiva:

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist escribe un `tuist.toml` en la raíz del repositorio con el identificador del proyecto e imprime un bloque `plugins { ... }`. Pégalo al principio de `settings.gradle.kts`:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

Haz una comprobación rápida con `./gradlew help`. Gradle debería cargarse sin errores. Si no encuentra el plugin, asegúrate de que el bloque esté en `settings.gradle.kts`, no en `build.gradle.kts`.

Todo lo siguiente es opcional e independiente.

## Caché de compilación remota

La caché de compilación local de Gradle almacena las salidas de las tareas en la máquina que las produjo. Dos desarrolladores en la misma rama acceden a la caché en su propio `~/.gradle` y no en el del otro, y la CI encuentra una caché nueva y vacía en cada trabajo.

La caché remota de Tuist amplía el mismo protocolo clave/valor que Gradle ya utiliza entre máquinas. Las salidas de una tarea se suben desde la máquina que la ejecutó primero y las descarga cualquier otra que encuentre las mismas entradas. Actívalo en `gradle.properties`:

```properties
org.gradle.caching=true
```

Luego compila en dos entornos:

```bash
./gradlew clean build --build-cache --info
```

Las tareas cacheables informan `FROM-CACHE` en la segunda ejecución. Abre **Caché** en el panel para ver las tasas de acierto a lo largo del tiempo.

## Análisis de compilaciones

Gradle emite los tiempos de las tareas al final de una compilación y, con `--profile`, genera un informe HTML por compilación. Ninguno agrega datos entre ejecuciones. Una tarea que se ha vuelto más lenta a lo largo de una serie de commits aparece igual en el informe de cualquier compilación individual que siempre lo hizo.

El plugin `dev.tuist` sube automáticamente los tiempos de las tareas de cada compilación al panel una vez aplicado el plugin. No hay nada extra que configurar. Abre **Compilaciones** en el panel después de tu próximo `./gradlew build` para ver la tendencia.

## Análisis de tests

Los informes de tests de Gradle se generan por compilación bajo `build/reports/tests/`. Un test que falla intermitentemente a lo largo de diez ejecuciones de CI parece, en cualquier informe concreto, un test estable que simplemente falló una vez.

El análisis de tests registra el resultado y la duración de cada tarea para cada ejecución de `./gradlew test` y correlaciona los resultados entre ejecuciones. Los tests inestables, los tests lentos y los fallos aparecen en la pestaña **Tests** del panel. Cuando se acumulan inestabilidades, ponlos en cuarentena desde el panel para que dejen de bloquear las fusiones.

El plugin también admite un **modo de pruebas de estrés** que vuelve a ejecutar los casos de test que introduce una compilación y marca aquellos que resultan inestables antes de que se integren. Añádelo a la extensión `tuist` en `settings.gradle.kts`:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## Análisis de paquetes

El Android Gradle Plugin informa del tamaño del `.aab` generado en la salida de la compilación. Ese número desaparece con la rama y comparar tamaños entre versiones es una tarea manual de contabilidad. Play Console muestra los mismos números, pero solo después de subir el artefacto.

El análisis de paquetes registra los tamaños de instalación y descarga de cada `.aab` (recomendado) o `.apk` y puede hacer fallar una comprobación de PR cuando se supera un umbral por rama. Añade esto a tu CI justo después del paso de compilación:

```bash
tuist inspect bundle App.aab
```

Abre **Análisis de paquetes → Android** en el panel para ver la tendencia y configurar umbrales.

## Previews

La pista de pruebas internas de Play Console añade un retraso de revisión y propagación en cada compartición. Enviar un `.apk` sin procesar por Slack o correo electrónico es más rápido, pero se pierde el rastro de a qué compilación se refiere un mensaje concreto.

Previews convierte una compilación en un enlace compartible que los destinatarios instalan con un solo comando:

```bash
tuist share App.apk
```

## Involucra al equipo

Los aciertos de caché, los análisis y las pruebas de estrés se potencian con el número de personas conectadas al proyecto. Invita a tus compañeros a la organización desde la configuración de la cuenta en el panel y configura el <.localized_link href="/guides/integrations/authentication/sso">inicio de sesión único</.localized_link> (Google, Okta, Microsoft) para que la incorporación sea un clic en lugar de un `tuist auth login` por persona.

Para la CI, no uses un inicio de sesión personal. Configura `TUIST_TOKEN` con alcance a tu proyecto (créalo desde la configuración del proyecto en el panel).

## Referencia completa del plugin

Todo lo tratado aquí es lo mínimo necesario para obtener valor de Tuist en un proyecto Gradle. Las opciones de configuración para el bloque de extensión `tuist`, el modo `stressNewTests` y la autenticación de CI están en la referencia [Instalar el plugin de Gradle](https://tuist.dev/en/docs/guides/install-gradle-plugin).
