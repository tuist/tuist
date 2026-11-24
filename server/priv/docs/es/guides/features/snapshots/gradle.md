---
{
  "title": "Gradle",
  "titleTemplate": ":title · Snapshots · Funcionalidades · Guías · Tuist",
  "description": "Captura cada vista previa de Compose o sube lo que graben Paparazzi y Roborazzi con el plugin de Gradle de Tuist."
}
---
# Instantáneas de Gradle {#gradle-snapshots}

> [!IMPORTANT]
> **Requisitos**
>
> - Instantáneas habilitadas para tu cuenta. Actualmente son solo por invitación: [ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso.
> - El <.localized_link href="/guides/install-gradle-plugin">plugin de Tuist para Gradle</.localized_link>.
> - [Paparazzi](https://github.com/cashapp/paparazzi) o [Roborazzi](https://github.com/takahirom/roborazzi) en los módulos de los que tomas instantáneas.

El plugin de Tuist para Gradle sube las imágenes que graban Paparazzi y Roborazzi, y Tuist las compara con la <.localized_link href="/guides/features/snapshots#how-it-works">línea base</.localized_link>. En los módulos que aplican Paparazzi, el plugin también genera un test que renderiza cada `@Preview` de Compose, para que no tengas que escribir tests de instantáneas a mano.

## Configuración {#set-up}

Habilita las instantáneas en tu `settings.gradle.kts`:

```kotlin
tuist {
    snapshots {
        enabled = true
        set = "android-phone" // Defaults to the Gradle project's path.
    }
}
```

## Ejecución {#run}

En CI, `./gradlew test` renderiza las vistas previas y las sube, y la compilación falla cuando han cambiado y nadie ha aprobado los cambios. Las ejecuciones locales no suben nada, porque subirían cambios no confirmados. Pasa `-Ptuist.snapshots=false` para desactivar las subidas en CI.

Las tareas de grabación de Paparazzi y Roborazzi, como `recordPaparazziDebug`, siempre suben las imágenes cuando las instantáneas están habilitadas.

## Opciones {#options}

El bloque `snapshots` acepta estas opciones:

- `enabled`: si las instantáneas se suben. El valor predeterminado es `false`.
- `set`: el conjunto dentro del cual se comparan las compilaciones. El valor predeterminado es la ruta del proyecto de Gradle.
- `directory`: el directorio con las imágenes a subir, relativo al proyecto de Gradle. El valor predeterminado es donde escribe el test de vista previa generado o la biblioteca de instantáneas.
- `failOnChanges`: si la compilación falla ante cambios que nadie ha aprobado. El valor predeterminado es `true`.
- `diffThreshold`: la proporción de píxeles, de 0 a 1, que pueden diferir antes de que una imagen se considere cambiada. El valor predeterminado es `0`.
- `previews { generateTests }`: si se genera el test de vista previa de Compose. El valor predeterminado es `true`.
- `previews { packageTrees }`: los paquetes que se exploran en busca de vistas previas. El valor predeterminado es el namespace de Android.
- `previews { includePrivatePreviews }`: si también se renderizan las funciones `@Preview` privadas. El valor predeterminado es `false`.
- `previews { theme }`: el tema de Android en el que se renderizan las vistas previas. El valor predeterminado es el de Paparazzi.
