---
{
  "title": "Gradle project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect a Gradle project to Tuist for a shared remote build cache, build and test insights across CI, bundle-size tracking, and preview links."
}
---
# Proyecto Gradle {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

Sigue esta ruta para conectar un proyecto Gradle existente con Tuist. El plugin de Gradle `dev.tuist` conecta la caché de compilación local de Gradle a la caché remota de Tuist y sube los datos de compilación y tests al dashboard, sin cambiar ni un solo comando `./gradlew`.

Cada sección a continuación comienza explicando qué falta hoy y luego te guía a través de la funcionalidad que cubre esa carencia.

## Requisitos previos

- Un proyecto Gradle con un `settings.gradle.kts` (o `settings.gradle`).
- La <.localized_link href="/guides/install-tuist">interfaz de línea de comandos de Tuist</.localized_link>.

## Conectar el proyecto

Desde la raíz del proyecto Gradle, ejecuta `tuist init`. Elige **Integrar un proyecto Gradle**, luego autentifícate en el navegador y selecciona la cuenta que debe ser propietaria del proyecto.

```bash
tuist init
```

Si estás realizando esto desde un agente de codificación o un script, ejecuta primero `tuist auth login` (el flujo del navegador espera a que presiones Enter), luego usa el formulario no interactivo:

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist escribe un `tuist.toml` en la raíz del repositorio con el identificador del proyecto e imprime un bloque `plugins { ... }`. Pégalo en la parte superior de `settings.gradle.kts`:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

Verifica el funcionamiento con `./gradlew help`. Gradle debería cargarse sin errores. Si no puede encontrar el plugin, asegúrate de que el bloque esté en `settings.gradle.kts`, no en `build.gradle.kts`.

Todo lo siguiente es opcional e independiente.

## Caché de compilación remota

La caché de compilación local de Gradle almacena las salidas de las tareas en la máquina que las produjo. Dos desarrolladores en la misma rama acceden a la caché en su propio `~/.gradle` y no en la del otro, y la CI accede a una caché nueva y vacía en cada trabajo.

La caché remota de Tuist extiende el mismo protocolo clave/valor que Gradle ya utiliza entre máquinas. Las salidas de una tarea se suben en la máquina que la ejecutó primero y las descarga cualquier otra persona que encuentre las mismas entradas. Habilítala en `gradle.properties`:

```properties
org.gradle.caching=true
```

Luego compila en dos entornos:

```bash
./gradlew clean build --build-cache --info
```

Las tareas almacenables en caché reportan `FROM-CACHE` en la segunda ejecución. Abre **Caché** en el dashboard para ver las tasas de acierto a lo largo del tiempo.

## Información de compilación

Gradle emite los tiempos de las tareas al final de una compilación y, con `--profile`, escribe un informe HTML por compilación. Ninguno de los dos agrega datos entre ejecuciones. Una tarea que se ha vuelto más lenta a lo largo de una serie de commits parece igual en el informe de cualquier compilación individual que como siempre lo hizo.

El plugin `dev.tuist` sube automáticamente los tiempos de las tareas de cada compilación al dashboard una vez que el plugin está aplicado. No hay nada extra que configurar. Abre **Compilaciones** en el dashboard después de tu próximo `./gradlew build` para ver la tendencia.

## Información de tests

Los informes de tests de Gradle se generan por compilación bajo `build/reports/tests/`. Un test que falla intermitentemente a lo largo de diez ejecuciones de CI parece, en cualquier informe dado, como un test estable que simplemente falló una vez.

La información de tests registra el resultado y la duración de cada tarea para cada ejecución de `./gradlew test` y correlaciona los resultados entre ejecuciones. Los tests inestables, los tests lentos y los fallos aparecen en la pestaña **Tests** del dashboard. Cuando se acumulan inestabilidades, ponlas en cuarentena desde el dashboard para que dejen de bloquear las fusiones.

El plugin también admite un **modo de prueba de estrés** que vuelve a ejecutar los casos de test que introduce una compilación y marca cualquiera que resulte inestable antes de que se integre. Añádelo a la extensión `tuist` en `settings.gradle.kts`:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## Información de bundles

El Android Gradle Plugin informa del tamaño del `.aab` generado en la salida de la compilación. Ese número desaparece con la rama, y comparar tamaños entre versiones es una tarea de contabilidad manual. Play Console informa de los mismos números, pero solo después de que el artefacto haya sido subido.

La información de bundles registra los tamaños de instalación y descarga para cada `.aab` (recomendado) o `.apk` y puede hacer fallar una comprobación de PR cuando se supera un umbral por rama. Añade esto a tu CI justo después de tu paso de compilación:

```bash
tuist inspect bundle App.aab
```

Abre **Información de bundles → Android** en el dashboard para ver la tendencia y configurar umbrales.

## Previews

La pista de test interna de Play Console añade un retraso de revisión y propagación en cada compartición. Enviar un `.apk` sin procesar a través de Slack o correo electrónico es más rápido, pero se pierde el rastro de a qué compilación se refiere un mensaje específico.

Previews convierte una compilación en un enlace compartible que los destinatarios instalan con un solo comando:

```bash
tuist share App.apk
```

## Involucra al equipo

Los aciertos de caché, la información y las pruebas de estrés se potencian con el número de personas conectadas al proyecto. Invita a tus compañeros a la organización desde la configuración de la cuenta en el dashboard y configura <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) para que la incorporación sea un clic en lugar de un `tuist auth login` por persona.

Para la CI, no uses un inicio de sesión personal. Establece `TUIST_TOKEN` con ámbito a tu proyecto (créalo desde la configuración del proyecto en el dashboard).

## Referencia completa del plugin

Todo lo cubierto aquí es lo mínimo necesario para obtener valor de Tuist en un proyecto Gradle. Las opciones de configuración para el bloque de extensión `tuist`, el modo `stressNewTests` y la autenticación de CI están en la referencia de [Instalar el plugin de Gradle](https://tuist.dev/en/docs/guides/install-gradle-plugin).
