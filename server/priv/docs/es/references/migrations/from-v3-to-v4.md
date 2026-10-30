---
{
  "title": "De v3 a v4",
  "titleTemplate": ":title · Migraciones · Referencias · Tuist",
  "description": "Esta página documenta cómo migrar la CLI de Tuist de la versión 3 a la versión 4."
}
---
# De Tuist v3 a v4 {#from-tuist-v3-to-v4}

Con el lanzamiento de [Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0), aprovechamos la oportunidad para introducir algunos cambios incompatibles en el proyecto, que creímos facilitarían su uso y mantenimiento a largo plazo. Este documento describe los cambios que deberás aplicar en tu proyecto para actualizar de Tuist 3 a Tuist 4.

### Eliminada la gestión de versiones mediante `tuistenv` {#dropped-version-management-through-tuistenv}

Antes de Tuist 4, el script de instalación instalaba una herramienta, `tuistenv`, que se renombraba a `tuist` durante la instalación. La herramienta se encargaba de instalar y activar versiones de Tuist, garantizando determinismo entre entornos. Con el objetivo de reducir la superficie de funcionalidades de Tuist, decidimos eliminar `tuistenv` en favor de [Mise](https://mise.jdx.dev/), una herramienta que realiza la misma tarea pero es más flexible y puede usarse con distintas herramientas. Si utilizabas `tuistenv`, tendrás que desinstalar la versión actual de Tuist ejecutando `curl -Ls https://uninstall.tuist.io | bash` y luego instalarla con el método de instalación que prefieras. Recomendamos encarecidamente usar Mise porque puede instalar y activar versiones de forma determinista entre entornos.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

> [!WARNING]
> **Mise en entornos de CI y proyectos de Xcode**
>
> Si decides adoptar el determinismo que ofrece Mise en todos los ámbitos, te recomendamos consultar la documentación sobre cómo usar Mise en [entornos de CI](https://mise.jdx.dev/continuous-integration.html) y [proyectos de Xcode](https://mise.jdx.dev/ide-integration.html#xcode).


> [!NOTE]
> **Homebrew es compatible**
>
> Ten en cuenta que aún puedes instalar Tuist mediante Homebrew, un gestor de paquetes popular para macOS. Puedes encontrar las instrucciones para instalar Tuist con Homebrew en la <.localized_link href="/guides/install-tuist#alternative-homebrew">guía de instalación</.localized_link>.


### Eliminados los constructores `init` de los modelos `ProjectDescription` {#dropped-init-constructors-from-projectdescription-models}

Con el objetivo de mejorar la legibilidad y expresividad de las API, decidimos eliminar los constructores `init` de todos los modelos `ProjectDescription`. Ahora cada modelo proporciona un constructor estático que puedes usar para crear instancias. Si utilizabas los constructores `init`, tendrás que actualizar tu proyecto para usar los constructores estáticos.

> [!TIP]
> **Convención de nomenclatura**
>
> La convención de nomenclatura que seguimos consiste en usar el nombre del modelo como nombre del constructor estático. Por ejemplo, el constructor estático del modelo `Target` es `Target.target`.


### Renombrado `--no-cache` a `--no-binary-cache` {#renamed-nocache-to-nobinarycache}

Dado que la opción `--no-cache` era ambigua, decidimos renombrarla a `--no-binary-cache` para dejar claro que hace referencia a la caché binaria. Si utilizabas la opción `--no-cache`, tendrás que actualizar tu proyecto para usar la opción `--no-binary-cache`.

### Renombrado `tuist fetch` a `tuist install` {#renamed-tuist-fetch-to-tuist-install}

Renombramos el comando `tuist fetch` a `tuist install` para alinearnos con la convención de la industria. Si utilizabas el comando `tuist fetch`, tendrás que actualizar tu proyecto para usar el comando `tuist install`.

### [Adoptar `Package.swift` como DSL para dependencias](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Antes de Tuist 4, podías definir dependencias en un archivo `Dependencies.swift`. Este formato propietario rompía la compatibilidad con herramientas como [Dependabot](https://github.com/dependabot) o [Renovatebot](https://github.com/renovatebot/renovate) para actualizar dependencias automáticamente. Además, introducía indirecciones innecesarias para los usuarios. Por ello, decidimos adoptar `Package.swift` como la única forma de definir dependencias en Tuist. Si utilizabas el archivo `Dependencies.swift`, tendrás que mover el contenido de tu `Tuist/Dependencies.swift` a un `Package.swift` en la raíz y usar la directiva `#if TUIST` para configurar la integración. Puedes leer más sobre cómo integrar dependencias de Swift Package <.localized_link href="/guides/features/projects/dependencies#swift-packages">aquí</.localized_link>

### Renombrado `tuist cache warm` a `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

Por brevedad, decidimos renombrar el comando `tuist cache warm` a `tuist cache`. Si utilizabas el comando `tuist cache warm`, tendrás que actualizar tu proyecto para usar el comando `tuist cache`.


### Renombrado `tuist cache print-hashes` a `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

Decidimos renombrar el comando `tuist cache print-hashes` a `tuist cache --print-hashes` para dejar claro que es una opción del comando `tuist cache`. Si utilizabas el comando `tuist cache print-hashes`, tendrás que actualizar tu proyecto para usar la opción `tuist cache --print-hashes`.

### Eliminados los perfiles de caché {#removed-caching-profiles}

Antes de Tuist 4, podías definir perfiles de caché en `Tuist/Config.swift`, que contenían una configuración para la caché. Decidimos eliminar esta funcionalidad porque podía generar confusión al usarla en el proceso de generación con un perfil distinto al utilizado para generar el proyecto. Además, podía llevar a los usuarios a usar un perfil de depuración para compilar una versión de producción de la app, lo que podría provocar resultados inesperados. En su lugar, introdujimos la opción `--configuration`, que puedes usar para especificar la configuración que deseas emplear al generar el proyecto. Si utilizabas perfiles de caché, tendrás que actualizar tu proyecto para usar la opción `--configuration`.

### Eliminada `--skip-cache` en favor de argumentos {#removed-skipcache-in-favor-of-arguments}

Eliminamos la opción `--skip-cache` del comando `generate` y ahora controlas para qué targets se omite la caché binaria mediante argumentos. Si utilizabas la opción `--skip-cache`, tendrás que actualizar tu proyecto para usar los argumentos.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [Eliminadas las capacidades de firma](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

La firma ya está resuelta por herramientas de la comunidad como [Fastlane](https://fastlane.tools/) y el propio Xcode, que lo hacen mucho mejor. Consideramos que la firma era un objetivo secundario para Tuist y que era mejor centrarse en las funcionalidades principales del proyecto. Si utilizabas las capacidades de firma de Tuist, que consistían en cifrar los certificados y los perfiles en el repositorio e instalarlos en los lugares adecuados durante la generación, quizá quieras replicar esa lógica en tus propios scripts que se ejecutan antes de la generación del proyecto. En particular:
  - Un script que descifre los certificados y los perfiles usando una clave almacenada en el sistema de archivos o en una variable de entorno, e instale los certificados en el llavero y los perfiles de aprovisionamiento en el directorio `~/Library/MobileDevice/Provisioning\ Profiles`.
  - Un script que pueda tomar perfiles y certificados existentes y cifrarlos.

> [!TIP]
> **Requisitos de firma**
>
> La firma requiere que los certificados correctos estén presentes en el llavero y que los perfiles de aprovisionamiento estén en el directorio `~/Library/MobileDevice/Provisioning\ Profiles`. Puedes usar la herramienta de línea de comandos `security` para instalar certificados en el llavero y el comando `cp` para copiar los perfiles de aprovisionamiento al directorio adecuado.


### Eliminada la integración con Carthage mediante `Dependencies.swift` {#dropped-carthage-integration-via-dependenciesswift}

Antes de Tuist 4, las dependencias de Carthage podían definirse en un archivo `Dependencies.swift`, que los usuarios podían obtener ejecutando `tuist fetch`. También consideramos que esto era un objetivo secundario para Tuist, especialmente teniendo en cuenta un futuro donde Swift Package Manager sería la forma preferida de gestionar dependencias. Si utilizabas dependencias de Carthage, tendrás que usar `Carthage` directamente para descargar los frameworks y XCFrameworks precompilados al directorio estándar de Carthage y luego hacer referencia a esos binarios desde tus targets usando los casos `TargetDependency.xcframework` y `TargetDependency.framework`.

> [!NOTE]
> **Carthage sigue siendo compatible**
>
> Algunos usuarios entendieron que eliminamos el soporte para Carthage. No fue así. El contrato entre Tuist y la salida de Carthage se basa en frameworks y XCFrameworks almacenados en el sistema. Lo único que ha cambiado es quién es responsable de obtener las dependencias. Antes era Tuist a través de Carthage, ahora es Carthage.


### Eliminada la API `TargetDependency.packagePlugin` {#dropped-the-targetdependencypackageplugin-api}

Antes de Tuist 4, podías definir una dependencia de plugin de paquete usando el caso `TargetDependency.packagePlugin`. Tras ver cómo Swift Package Manager introducía nuevos tipos de paquetes, decidimos iterar sobre la API hacia algo más flexible y preparado para el futuro. Si utilizabas `TargetDependency.packagePlugin`, tendrás que usar `TargetDependency.package` en su lugar y pasar el tipo de paquete que deseas utilizar como argumento.

### [Eliminadas las APIs obsoletas](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Eliminamos las APIs que estaban marcadas como obsoletas en Tuist 3. Si utilizabas alguna de las APIs obsoletas, tendrás que actualizar tu proyecto para usar las nuevas APIs.
