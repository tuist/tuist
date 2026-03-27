---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# De Tuist v3 a v4 {#from-tuist-v3-to-v4}

Con el lanzamiento de [Tuist
4](https://github.com/tuist/tuist/releases/tag/4.0.0), aprovechamos la
oportunidad para introducir algunos cambios de última hora en el proyecto, que
creíamos que harían que el proyecto fuera más fácil de usar y mantener a largo
plazo. Este documento describe los cambios que tendrás que hacer en tu proyecto
para actualizar de Tuist 3 a Tuist 4.

### Abandonada la gestión de versiones a través de `tuistenv` {#dropped-version-management-through-tuistenv}

Antes de Tuist 4, el script de instalación instalaba una herramienta,
`tuistenv`, que era renombrada a `tuist` en el momento de la instalación. La
herramienta se encargaría de instalar y activar versiones de Tuist asegurando el
determinismo entre entornos. Con el objetivo de reducir la superficie de
características de Tuist, decidimos abandonar `tuistenv` en favor de
[Mise](https://mise.jdx.dev/), una herramienta que hace el mismo trabajo pero es
más flexible y puede usarse en diferentes herramientas. Si estabas usando
`tuistenv`, tendrás que desinstalar la versión actual de Tuist ejecutando `curl
-Ls https://uninstall.tuist.io | bash` y luego instalarlo usando el método de
instalación de tu elección. Recomendamos encarecidamente el uso de Mise porque
es capaz de instalar y activar versiones de forma determinista en todos los
entornos.

::: grupo de códigos

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

::: warning MISE IN CI ENVIRONMENTS AND XCODE PROJECTS
<!-- -->
Si decide adoptar el determinismo que aporta Mise en todos los ámbitos, le
recomendamos que consulte la documentación sobre cómo utilizar Mise en [entornos
CI](https://mise.jdx.dev/continuous-integration.html) y [proyectos
Xcode](https://mise.jdx.dev/ide-integration.html#xcode).
<!-- -->
:::

::: info HOMEBREW IS SUPPORTED
<!-- -->
Ten en cuenta que aún puedes instalar Tuist usando Homebrew, que es un popular
gestor de paquetes para macOS. Puedes encontrar las instrucciones sobre cómo
instalar Tuist usando Homebrew en la
<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">guía de instalación</LocalizedLink>.
<!-- -->
:::

### Eliminado `init` constructores de `ProjectDescription` modelos {#dropped-init-constructors-from-projectdescription-models}

Con el objetivo de mejorar la legibilidad y expresividad de las APIs, hemos
decidido eliminar los constructores `init` de todos los modelos
`ProjectDescription`. Cada modelo proporciona ahora un constructor estático que
puede utilizar para crear instancias de los modelos. Si estabas utilizando los
constructores `init`, tendrás que actualizar tu proyecto para utilizar los
constructores estáticos en su lugar.

::: tip NAMING CONVENTION
<!-- -->
La convención de nomenclatura que seguimos es utilizar el nombre del modelo como
nombre del constructor estático. Por ejemplo, el constructor estático del modelo
`Target` es `Target.target`.
<!-- -->
:::

### Se ha cambiado el nombre de `--no-cache` a `--no-binary-cache` {#renamed-nocache-to-nobinarycache}

Debido a que la opción `--no-cache` era ambigua, hemos decidido renombrarla a
`--no-binary-cache` para dejar claro que se refiere a la caché binaria. Si
estabas usando la opción `--no-cache`, tendrás que actualizar tu proyecto para
usar la opción `--no-binary-cache`.

### Renombrado `tuist fetch` a `tuist install` {#renamed-tuist-fetch-to-tuist-install}

Hemos renombrado el comando `tuist fetch` a `tuist install` para alinearlo con
la convención de la industria. Si estaba utilizando el comando `tuist fetch`,
tendrá que actualizar su proyecto para utilizar en su lugar el comando `tuist
install`.

### [Adoptar `Package.swift` como DSL para dependencias](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Antes de Tuist 4, podías definir las dependencias en un archivo
`Dependencies.swift`. Este formato propietario rompía el soporte en herramientas
como [Dependabot](https://github.com/dependabot) o
[Renovatebot](https://github.com/renovatebot/renovate) para actualizar
automáticamente las dependencias. Además, introducía indirecciones innecesarias
para los usuarios. Por lo tanto, decidimos adoptar `Package.swift` como única
forma de definir dependencias en Tuist. Si estabas usando el archivo
`Dependencies.swift`, tendrás que mover el contenido de tu
`Tuist/Dependencies.swift` a un `Package.swift` en la raíz, y usar la directiva
`#if TUIST` para configurar la integración. Puede leer más sobre cómo integrar
dependencias de paquetes Swift
<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">aquí</LocalizedLink>

### Renombrado `tuist cache warm` a `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

Por brevedad, hemos decidido renombrar el comando `tuist cache warm` a `tuist
cache`. Si estaba utilizando el comando `tuist cache warm`, tendrá que
actualizar su proyecto para utilizar en su lugar el comando `tuist cache`.


### Renombrado `tuist cache print-hashes` a `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

Hemos decidido renombrar el comando `tuist cache print-hashes` a `tuist cache
--print-hashes` para dejar claro que es una bandera del comando `tuist cache`.
Si estaba utilizando el comando `tuist cache print-hashes`, tendrá que
actualizar su proyecto para utilizar el comando `tuist cache --print-hashes`.

### Perfiles de caché eliminados {#removed-caching-profiles}

Antes de Tuist 4, podías definir perfiles de caché en `Tuist/Config.swift` que
contenía una configuración para la caché. Decidimos eliminar esta característica
porque podía llevar a confusión al utilizarla en el proceso de generación con un
perfil distinto al que se utilizó para generar el proyecto. Además, podía dar
lugar a que los usuarios utilizaran un perfil de depuración para generar una
versión de lanzamiento de la aplicación, lo que podría dar lugar a resultados
inesperados. En su lugar, hemos introducido la opción `--configuration`, que
puedes utilizar para especificar la configuración que deseas utilizar al generar
el proyecto. Si estabas utilizando perfiles de caché, tendrás que actualizar tu
proyecto para utilizar la opción `--configuration` en su lugar.

### Eliminado `--skip-cache` en favor de los argumentos {#removed-skipcache-in-favor-of-arguments}

Hemos eliminado la opción `--skip-cache` del comando `generate` en favor de
controlar para qué objetivos se debe omitir la caché binaria utilizando los
argumentos. Si estaba utilizando la opción `--skip-cache`, tendrá que actualizar
su proyecto para utilizar los argumentos en su lugar.

::: grupo de códigos

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [Capacidades de firma abandonadas](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

La firma ya está resuelta por herramientas de la comunidad como
[Fastlane](https://fastlane.tools/) y el propio Xcode, que lo hacen mucho mejor.
Pensamos que firmar era un objetivo demasiado ambicioso para Tuist, y que era
mejor centrarse en las características principales del proyecto. Si estabas
usando las capacidades de firma de Tuist, que consistían en cifrar los
certificados y perfiles en el repositorio e instalarlos en los lugares adecuados
en el momento de la generación, puede que quieras replicar esa lógica en tus
propios scripts que se ejecutan antes de la generación del proyecto. En
particular:
  - Una secuencia de comandos que descifra los certificados y perfiles
    utilizando una clave almacenada en el sistema de archivos o en una variable
    de entorno, e instala los certificados en el llavero y los perfiles de
    aprovisionamiento en el directorio `~/Library/MobileDevice/Provisioning\
    Profiles`.
  - Un script que puede tomar perfiles y certificados existentes y encriptarlos.

::: tip SIGNING REQUIREMENTS
<!-- -->
La firma requiere la presencia de los certificados adecuados en el llavero y de
los perfiles de aprovisionamiento en el directorio
`~/Library/MobileDevice/Provisioning\ Profiles`. Puede utilizar la herramienta
de línea de comandos `security` para instalar certificados en el llavero y el
comando `cp` para copiar los perfiles de aprovisionamiento en el directorio
correcto.
<!-- -->
:::

### Eliminada la integración de Carthage a través de `Dependencies.swift` {#dropped-carthage-integration-via-dependenciesswift}

Antes de Tuist 4, las dependencias de Carthage podían definirse en un archivo
`Dependencies.swift`, que los usuarios podían obtener ejecutando `tuist fetch`.
También pensamos que este era un objetivo a alcanzar para Tuist, especialmente
teniendo en cuenta un futuro en el que el Gestor de Paquetes Swift sería la
forma preferida de gestionar las dependencias. Si estabas usando dependencias de
Carthage, tendrás que usar `Carthage` directamente para extraer los frameworks
precompilados y XCFrameworks al directorio estándar de Carthage, y luego
referenciar esos binarios desde tus tagets usando los casos
`TargetDependency.xcframework` y `TargetDependency.framework`.

::: info CARTHAGE IS STILL SUPPORTED
<!-- -->
Algunos usuarios entendieron que habíamos dejado de dar soporte a Carthage. No
lo hicimos. El contrato entre Tuist y la salida de Carthage es a frameworks
almacenados en el sistema y XCFrameworks. Lo único que ha cambiado es quién es
el responsable de obtener las dependencias. Antes era Tuist a través de
Carthage, ahora es Carthage.
<!-- -->
:::

### Eliminada la API `TargetDependency.packagePlugin` {#dropped-the-targetdependencypackageplugin-api}

Antes de Tuist 4, podías definir una dependencia de plugin de paquete usando el
caso `TargetDependency.packagePlugin`. Después de ver que el Gestor de Paquetes
Swift introducía nuevos tipos de paquetes, decidimos iterar en la API hacia algo
que fuera más flexible y preparado para el futuro. Si estabas usando
`TargetDependency.packagePlugin`, tendrás que usar `TargetDependency.package` en
su lugar, y pasar el tipo de paquete que quieras usar como argumento.

### [APIs obsoletas eliminadas](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Hemos eliminado las APIs que estaban marcadas como obsoletas en Tuist 3. Si
estabas utilizando alguna de las APIs obsoletas, tendrás que actualizar tu
proyecto para utilizar las nuevas APIs.
