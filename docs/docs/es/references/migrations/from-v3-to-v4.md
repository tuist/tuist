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
oportunidad para introducir algunos cambios importantes en el proyecto, que
creemos que lo harán más fácil de usar y mantener a largo plazo. Este documento
describe los cambios que deberá realizar en su proyecto para actualizar de Tuist
3 a Tuist 4.

### Gestión de versiones eliminada a través de `tuistenv` {#dropped-version-management-through-tuistenv}

Antes de Tuist 4, el script de instalación instalaba una herramienta,
`tuistenv`, que se renombraría a `tuist` en el momento de la instalación. La
herramienta se encargaba de instalar y activar las versiones de Tuist,
garantizando el determinismo en todos los entornos. Con el objetivo de reducir
la superficie de características de Tuist, decidimos eliminar `tuistenv` en
favor de [Mise](https://mise.jdx.dev/), una herramienta que hace el mismo
trabajo pero es más flexible y se puede utilizar en diferentes herramientas. Si
utilizabas `tuistenv`, tendrás que desinstalar la versión actual de Tuist
ejecutando `curl -Ls https://uninstall.tuist.io | bash` y, a continuación,
instalarla utilizando el método de instalación que prefieras. Recomendamos
encarecidamente el uso de Mise, ya que es capaz de instalar y activar versiones
de forma determinista en todos los entornos.

::: grupo de códigos

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

::: warning MISE IN CI ENVIRONMENTS AND XCODE PROJECTS
<!-- -->
Si decides adoptar el determinismo que Mise transmite en todos los ámbitos, te
recomendamos que consultes la documentación sobre cómo utilizar Mise en
[entornos CI](https://mise.jdx.dev/continuous-integration.html) y [proyectos
Xcode](https://mise.jdx.dev/ide-integration.html#xcode).
<!-- -->
:::

::: info HOMEBREW IS SUPPORTED
<!-- -->
Ten en cuenta que aún puedes instalar Tuist utilizando Homebrew, que es un
popular gestor de paquetes para macOS. Puedes encontrar las instrucciones sobre
cómo instalar Tuist utilizando Homebrew en la
<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">guía
de instalación</LocalizedLink>.
<!-- -->
:::

### Se han eliminado los constructores `init` de `ProjectDescription` models {#dropped-init-constructors-from-projectdescription-models}

Con el objetivo de mejorar la legibilidad y la expresividad de las API, hemos
decidido eliminar los constructores `init` de todos los modelos
`ProjectDescription`. Ahora, todos los modelos proporcionan un constructor
estático que se puede utilizar para crear instancias de los modelos. Si
utilizabas los constructores `init`, tendrás que actualizar tu proyecto para
utilizar los constructores estáticos en su lugar.

::: tip NAMING CONVENTION
<!-- -->
La convención de nomenclatura que seguimos es utilizar el nombre del modelo como
nombre del constructor estático. Por ejemplo, el constructor estático para el
modelo `Target` es `Target.target`.
<!-- -->
:::

### Se ha cambiado el nombre de `--no-cache` a `--no-binary-cache.` {#renamed-nocache-to-nobinarycache}

Debido a que el indicador `--no-cache` era ambiguo, decidimos cambiarle el
nombre a `--no-binary-cache` para dejar claro que se refiere a la caché binaria.
Si utilizabas el indicador `--no-cache`, tendrás que actualizar tu proyecto para
utilizar el indicador `--no-binary-cache` en su lugar.

### Renombrado `tuist fetch` a `tuist install` {#renamed-tuist-fetch-to-tuist-install}

Hemos cambiado el nombre del comando `tuist fetch` a `tuist install` para
alinearlo con la convención del sector. Si utilizabas el comando `tuist fetch`,
tendrás que actualizar tu proyecto para utilizar el comando `tuist install` en
su lugar.

### [Adopta `Package.swift` como DSL para las dependencias](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Antes de Tuist 4, se podían definir las dependencias en un archivo
`Dependencies.swift`. Este formato propietario impedía que herramientas como
[Dependabot](https://github.com/dependabot) o
[Renovatebot](https://github.com/renovatebot/renovate) actualizaran
automáticamente las dependencias. Además, introducía indirecciones innecesarias
para los usuarios. Por lo tanto, decidimos adoptar `Package.swift` como la única
forma de definir dependencias en Tuist. Si utilizabas el archivo
`Dependencies.swift`, tendrás que mover el contenido de tu
`Tuist/Dependencies.swift` a un `Package.swift` en la raíz, y utilizar la
directiva `#if TUIST` para configurar la integración. Puedes leer más sobre cómo
integrar las dependencias de Swift Package
<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">
aquí.</LocalizedLink>

### Renombrado `tuist cache warm` a `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

Para abreviar, hemos decidido cambiar el nombre del comando « `tuist cache warm`
» por « `tuist cache` ». Si utilizabas el comando « `tuist cache warm` »,
tendrás que actualizar tu proyecto para utilizar el comando « `tuist cache` » en
su lugar.


### Se ha cambiado el nombre de « `tuist cache print-hashes» (` ) a « `tuist cache --print-hashes».` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

Hemos decidido cambiar el nombre del comando `tuist cache print-hashes` por
`tuist cache --print-hashes` para dejar claro que se trata de un indicador del
comando `tuist cache`. Si utilizabas el comando `tuist cache print-hashes`,
tendrás que actualizar tu proyecto para utilizar el indicador `tuist cache
--print-hashes` en su lugar.

### Perfiles de almacenamiento en caché eliminados. {#removed-caching-profiles}

Antes de Tuist 4, se podían definir perfiles de almacenamiento en caché en
`Tuist/Config.swift`, que contenía una configuración para la caché. Decidimos
eliminar esta función porque podía generar confusión al utilizarla en el proceso
de generación con un perfil distinto al que se utilizó para generar el proyecto.
Además, podía llevar a los usuarios a utilizar un perfil de depuración para
crear una versión de lanzamiento de la aplicación, lo que podía dar lugar a
resultados inesperados. En su lugar, hemos introducido la opción
`--configuration`, que se puede utilizar para especificar la configuración que
se desea utilizar al generar el proyecto. Si utilizabas perfiles de
almacenamiento en caché, tendrás que actualizar tu proyecto para utilizar la
opción `--configuration` en su lugar.

### Se ha eliminado `--skip-cache` en favor de los argumentos. {#removed-skipcache-in-favor-of-arguments}

Hemos eliminado la bandera `--skip-cache` del comando `generate` para poder
controlar para qué objetivos se debe omitir la caché binaria mediante el uso de
argumentos. Si utilizabas la bandera `--skip-cache`, tendrás que actualizar tu
proyecto para utilizar los argumentos en su lugar.

::: grupo de códigos

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [Capacidades de firma eliminadas](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

La firma ya está resuelta por herramientas comunitarias como
[Fastlane](https://fastlane.tools/) y el propio Xcode, que hacen un trabajo
mucho mejor en ese aspecto. Consideramos que la firma era un objetivo ambicioso
para Tuist y que era mejor centrarse en las características principales del
proyecto. Si utilizabas las capacidades de firma de Tuist, que consistían en
cifrar los certificados y perfiles del repositorio e instalarlos en los lugares
adecuados en el momento de la generación, es posible que desees replicar esa
lógica en tus propios scripts que se ejecutan antes de la generación del
proyecto. En concreto:
  - Un script que descifra los certificados y perfiles utilizando una clave
    almacenada en el sistema de archivos o en una variable de entorno, e instala
    los certificados en el llavero y los perfiles de aprovisionamiento en el
    directorio `~/Library/MobileDevice/Provisioning\ Profiles`.
  - Un script que puede tomar perfiles y certificados existentes y cifrarlos.

::: tip SIGNING REQUIREMENTS
<!-- -->
Para firmar es necesario que los certificados correctos estén presentes en el
llavero y que los perfiles de aprovisionamiento estén presentes en el directorio
`~/Library/MobileDevice/Provisioning\ Profiles`. Puede utilizar la herramienta
de línea de comandos `security` para instalar certificados en el llavero y el
comando `cp` para copiar los perfiles de aprovisionamiento al directorio
correcto.
<!-- -->
:::

### Se ha eliminado la integración de Carthage a través de `Dependencies.swift.` {#dropped-carthage-integration-via-dependenciesswift}

Antes de Tuist 4, las dependencias de Carthage se podían definir en un archivo
`Dependencies.swift`, que los usuarios podían obtener ejecutando `tuist fetch`.
También consideramos que este era un objetivo ambicioso para Tuist,
especialmente teniendo en cuenta un futuro en el que Swift Package Manager sería
la forma preferida de gestionar las dependencias. Si utilizabas dependencias de
Carthage, tendrás que utilizar `Carthage` directamente para extraer los marcos y
XCFrameworks precompilados al directorio estándar de Carthage y, a continuación,
hacer referencia a esos binarios desde tus objetivos utilizando los casos
`TargetDependency.xcframework` y `TargetDependency.framework`.

::: info CARTHAGE IS STILL SUPPORTED
<!-- -->
Algunos usuarios entendieron que habíamos dejado de ofrecer soporte para
Carthage. No es así. El contrato entre Tuist y Carthage se refiere a los marcos
almacenados en el sistema y a los XCFrameworks. Lo único que ha cambiado es
quién se encarga de obtener las dependencias. Antes era Tuist a través de
Carthage, ahora es Carthage.
<!-- -->
:::

### Se ha eliminado `TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api}

Antes de Tuist 4, se podía definir una dependencia de complemento de paquete
utilizando el caso `TargetDependency.packagePlugin`. Después de ver que Swift
Package Manager introducía nuevos tipos de paquetes, decidimos iterar la API
hacia algo que fuera más flexible y preparado para el futuro. Si utilizabas
`TargetDependency.packagePlugin`, tendrás que utilizar
`TargetDependency.package` en su lugar y pasar el tipo de paquete que deseas
utilizar como argumento.

### [API obsoletas eliminadas](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Hemos eliminado las API que estaban marcadas como obsoletas en Tuist 3. Si
utilizabas alguna de las API obsoletas, tendrás que actualizar tu proyecto para
utilizar las nuevas API.
