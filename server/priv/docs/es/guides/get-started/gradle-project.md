---
{
  "title": "Proyecto Gradle",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Conecta un proyecto Gradle a Tuist para obtener una caché de compilación remota compartida, análisis de compilaciones y tests en CI, seguimiento del tamaño del bundle y enlaces a previews."
}
---
# Proyecto Gradle {#gradle-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/gradle-project
```

:::

Sigue esta ruta para conectar un proyecto Gradle existente a Tuist. El plugin de Gradle `dev.tuist` conecta la caché de compilación local de Gradle con la caché remota de Tuist y sube los datos de compilación y tests al panel, sin cambiar ni un solo comando `./gradlew`.

Cada sección a continuación comienza explicando qué falta hoy y luego te guía por la funcionalidad que cubre esa carencia.

## Requisitos previos

- Un proyecto Gradle con un `settings.gradle.kts` (o `settings.gradle`).
- La <.localized_link href="/guides/install-tuist">interfaz de línea de comandos de Tuist</.localized_link>.

## Conectar el proyecto

Desde la raíz del proyecto Gradle, ejecuta `tuist init`. Elige **Integrar un proyecto Gradle**, autentícate en el navegador y selecciona la cuenta que debe ser propietaria del proyecto.

```bash
tuist init
```

Si lo haces desde un agente de programación o un script, ejecuta primero `tuist auth login` (el flujo del navegador espera a que pulses Intro) y luego usa la forma no interactiva:

```bash
tuist init --build-system gradle --name <project-handle> --account <account>
```

Tuist escribe un `tuist.toml` en la raíz del repositorio con el identificador del proyecto e imprime un bloque `plugins { ... }`. Pégalo al principio de `settings.gradle.kts`:

<!-- @snippet: ../_gradle-plugin-block -->

Haz una comprobación rápida con `./gradlew help`. Gradle debería cargarse sin errores. Si no encuentra el plugin, asegúrate de que el bloque esté en `settings.gradle.kts`, no en `build.gradle.kts`.

Todo lo siguiente es opcional e independiente.

## Caché de compilación remota

La caché de compilación local de Gradle almacena las salidas de las tareas en la máquina que las generó. Dos desarrolladores en la misma rama aciertan la caché en su propio `~/.gradle` y no en la del otro, y la CI accede a una caché nueva y vacía en cada trabajo.

La caché remota de Tuist amplía el mismo protocolo clave/valor que Gradle ya usa entre máquinas. Las salidas de una tarea se suben desde la máquina que la ejecutó primero y las descarga cualquier otra que encuentre las mismas entradas. Actívala en `gradle.properties`:

```properties
org.gradle.caching=true
```

Luego compila en dos entornos:

```bash
./gradlew clean build --build-cache --info
```

Las tareas almacenables en caché informan `FROM-CACHE` en la segunda ejecución. Abre **Caché** en el panel para ver las tasas de aciertos a lo largo del tiempo.

## Análisis de compilaciones

Gradle emite los tiempos de las tareas al final de una compilación y, con `--profile`, genera un informe HTML por compilación. Ninguno agrega datos entre ejecuciones. Una tarea que se ha vuelto más lenta a lo largo de una serie de commits aparece igual en el informe de cualquier compilación individual que siempre lo hizo.

El plugin `dev.tuist` sube automáticamente los tiempos de las tareas de cada compilación al panel una vez aplicado. No hay nada extra que configurar. Abre **Compilaciones** en el panel después de tu próximo `./gradlew build` para ver la tendencia.

## Análisis de tests

Los informes de tests de Gradle se generan por compilación bajo `build/reports/tests/`. Un test que falla intermitentemente a lo largo de diez ejecuciones de CI parece, en cualquier informe concreto, un test estable que simplemente falló una vez.

El análisis de tests registra el resultado y la duración de cada tarea para cada ejecución de `./gradlew test` y correlaciona los resultados entre ejecuciones. Los tests inestables, los tests lentos y los fallos aparecen en la pestaña **Tests** del panel. Cuando los casos inestables se acumulan, ponlos en cuarentena desde el panel para que dejen de bloquear los merges.

El plugin también admite un **modo de pruebas de estrés** que vuelve a ejecutar los casos de test que introduce una compilación y marca aquellos que resultan inestables antes de que se integren. Añádelo a la extensión `tuist` en `settings.gradle.kts`:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

## Cobertura de código

JaCoCo genera un informe de cobertura por tarea de test y por máquina. Nada combina los informes de los trabajos de CI de un commit ni muestra si la cobertura de una rama subió o bajó.

El plugin puede medir tus tests unitarios de JVM y Android con JaCoCo y subir la cobertura con cada ejecución de tests. Tuist consolida las ejecuciones de un commit, incluidas las particiones, en una única cifra. Actívalo en la extensión `tuist` de `settings.gradle.kts`:

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

Abre **Cobertura de código** en el panel para verlo por commit y por archivo. Consulta <.localized_link href="/guides/features/test-code-coverage/gradle">Cobertura de código en Gradle</.localized_link> para completar un commit en CI y configurar Robolectric.

## Análisis de paquetes

El Android Gradle Plugin informa del tamaño del `.aab` generado en la salida de la compilación. Ese número desaparece con la rama y comparar tamaños entre versiones es una tarea manual de contabilidad. Play Console informa de los mismos números, pero solo después de subir el artefacto.

El análisis de paquetes registra los tamaños de instalación y descarga de cada `.aab` (recomendado) o `.apk` y puede hacer fallar una comprobación de PR cuando se supera un umbral por rama. Añade esto a tu CI justo después del paso de compilación:

```bash
tuist inspect bundle App.aab
```

Abre **Análisis de paquetes → Android** en el panel para ver la tendencia y configurar umbrales.

## Previews

La pista de pruebas internas de Play Console añade un retraso de revisión y propagación en cada compartición. Enviar un `.apk` sin procesar por Slack o correo electrónico es más rápido, pero se pierde el rastro de a qué compilación se refiere un mensaje concreto.

El plugin puede compilar y publicar directamente una variante de aplicación, sin necesidad de una subida separada por CLI:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

Solicitar una tarea `tuistShare<Variant>` habilita la publicación para esa invocación; las compilaciones normales nunca suben previews. Consulta <.localized_link href="/guides/features/previews/gradle">Previews en Gradle</.localized_link> para conocer los APK compatibles, la firma y la instalación.

## Involucra al equipo

Los aciertos de caché, los análisis y las pruebas de estrés se potencian con el número de personas conectadas al proyecto. Invita a tus compañeros a la organización desde la configuración de la cuenta en el panel y configura <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) para que la incorporación sea un clic en lugar de un `tuist auth login` por persona.

Para la CI, no uses un inicio de sesión personal. Autentícate con la identidad OIDC de tu proveedor de CI o crea un token de cuenta con la preset **CI** en el panel y configúralo como `TUIST_TOKEN`. Consulta <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Autenticación del plugin de Gradle</.localized_link>.

## Referencia completa del plugin

Todo lo que se cubre aquí es el mínimo necesario para obtener valor de Tuist en un proyecto Gradle. Las opciones de configuración para el bloque de extensión `tuist`, el modo `stressNewTests` y la autenticación de CI se encuentran en la referencia [Instalar el plugin de Gradle](https://tuist.dev/en/docs/guides/install-gradle-plugin).
