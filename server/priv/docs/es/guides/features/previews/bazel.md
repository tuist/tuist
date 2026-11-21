---
{
  "title": "Previews de Bazel",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Publica apps de Android, apps de Apple y herramientas de línea de comandos como previews desde Bazel."
}
---
# Previsualizaciones de Bazel

Publica APKs de Android, aplicaciones para el simulador de Apple y macOS, y herramientas de línea de comandos desde tus objetivos de Bazel existentes. Añade un objetivo de previsualización para cada salida que quieras compartir; tus compilaciones habituales permanecen sin cambios.

## Configuración

Añade [`rules_tuist` del repositorio de Tuist](https://github.com/tuist/tuist/tree/main/bazel) a `MODULE.bazel`, fijando el commit que deseas usar:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

Mantén tus objetivos de aplicación existentes, los SDK nativos y la configuración de firma. Bazel proporciona las herramientas de publicación.

Inicia sesión directamente desde Bazel:

```bash
bazel run @rules_tuist//:login
```

Esto comparte las credenciales con la CLI de Tuist y el plugin de Gradle; un inicio de sesión existente también funciona. En CI, usa `TUIST_TOKEN` o ejecuta el objetivo de login con la <.localized_link href="/guides/integrations/continuous-integration">autenticación OIDC</.localized_link> de Tuist. Nunca pongas credenciales en archivos BUILD o atributos de reglas. Pasa `-- --url https://tuist.example.com` para iniciar sesión en una instancia autoalojada.

Carga solo el adaptador que necesites en tu `BUILD.bazel`:

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

Para aplicaciones de Apple:

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

Para objetivos ejecutables como `cc_binary`:

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

La previsualización ejecutable incluye los archivos de runtime declarados por el objetivo. Declara las bibliotecas y recursos que tu herramienta necesita en su objetivo de Bazel y usa rutas que funcionen fuera de tu directorio de compilación.

## Compilar y publicar

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

Reemplaza las etiquetas de la aplicación y de la plataforma del simulador con las tuyas. Pasa `--url` para un origen de Tuist autoalojado y `--revision` para asociar un commit de Git.

Pasa `--publish --project account/project` para compartir una compilación exitosa. Sin `--publish`, o con `--no-publish`, no se sube nada y no se requiere inicio de sesión. Un `bazel build` habitual nunca publica, incluso en aciertos de caché. `tuist bazel setup` habilita el almacenamiento en caché y los insights, no la publicación.

## Salidas admitidas

- **Android:** APKs de aplicación firmadas, incluidas las compilaciones de depuración. Instala las build-tools y las herramientas de línea de comandos del SDK de Android, y configura `ANDROID_HOME` o `ANDROID_SDK_ROOT`. Los APKs de test y los Android App Bundles no son compatibles.
- **Apple:** aplicaciones para el simulador y macOS firmadas ad-hoc, compiladas y verificadas en macOS. Las compilaciones para dispositivos físicos, frameworks, extensiones y tests no son compatibles. Usa la salida de archivo en lugar de los tree archives experimentales.
- **Herramientas de línea de comandos:** ejecutables para macOS o Linux para arm64 o x86_64, incluidos binarios universales de macOS. Los scripts requieren una shebang y un intérprete en el sistema del destinatario. Declara las dependencias de runtime en tu objetivo; Tuist no instala bibliotecas faltantes ni runtimes de lenguaje.

## Repetición de caché, fallos y retención

Repetir la misma publicación reutiliza la previsualización existente sin volver a subirla, incluso cuando Bazel restaura la compilación desde la caché. Cambiar la salida, el track o la revisión crea una nueva publicación. Un fallo de subida hace fallar el comando; puedes volver a ejecutarlo para comprobar si la publicación se completó antes de intentarlo de nuevo.

El comando enlaza a las previsualizaciones de tu proyecto, donde el procesamiento puede tardar un momento. Las previsualizaciones usan la visibilidad predeterminada del proyecto.

Las publicaciones de artefactos caducan después de 30 días en Tuist alojado. Las instancias autoalojadas usan `TUIST_APP_PREVIEW_RETENTION_DAYS`; dejarlo sin configurar deshabilita la caducidad para esta familia. Los registros de publicación caducados no pueden revivirse repitiendo la misma intención.

Consulta <.localized_link href="/guides/features/previews#run-a-preview">Ejecutar una previsualización</.localized_link> para ejecutar compilaciones publicadas, acceso, tracks y badges de README.

## Previsualizaciones de Apple

Para previsualizaciones del simulador de Apple y macOS, consulta las <.localized_link href="/guides/features/previews/run/macos">instrucciones de la aplicación complementaria de Tuist para macOS</.localized_link>. Esto no cambia los requisitos de elegibilidad de la aplicación ni de firma de Bazel.

## Flujos de trabajo relacionados {#publish-from-once}

Las integraciones existentes de Struo tienen una <.localized_link href="/guides/features/previews/struo">guía de publicación de artefactos</.localized_link> separada. Ambos flujos de trabajo mantienen la publicación separada de la ejecución del grafo en caché.
