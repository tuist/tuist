---
{
  "title": "Imágenes",
  "titleTemplate": ":title · Runners · Funcionalidades · Guías · Tuist",
  "description": "Qué viene preinstalado en los Runners de Tuist: las imágenes de macOS con Xcode, simuladores y la cadena de herramientas Metal, y las imágenes de Ubuntu con Docker y el SDK de Android."
}
---
# Imágenes {#images}

Cada trabajo de Tuist Runners se inicia en una máquina virtual nueva arrancada desde una imagen de runner. Tu <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> elige la imagen: la plataforma, la versión de Xcode en macOS y la release de Ubuntu en Linux. La VM se descarta cuando termina el trabajo, por lo que cualquier cosa que instale el trabajo desaparece para el siguiente.

Las imágenes siguen a los runners alojados en GitHub en lo que importa para los flujos de trabajo: el mismo usuario, las rutas de home y workspace, `ImageOS`, `sudo` sin contraseña y las herramientas que esperan la mayoría de flujos de iOS, macOS y Linux. Son intencionadamente más pequeñas que las de GitHub, así que las diferencias se enumeran para cada plataforma a continuación.

## Elegir una imagen {#choosing-an-image}

- **Xcode, SDKs de Apple o simuladores:** un perfil de macOS fijado a la versión de Xcode con la que compila tu proyecto.
- **Docker, compilaciones y emuladores de Android, u otras herramientas de Linux:** un perfil de Linux en Ubuntu 24.04.
- **Una dependencia que aún no es compatible con Ubuntu 24.04:** un perfil de Linux en Ubuntu 22.04.

En macOS eliges la versión de Xcode, no la imagen: cada versión de Xcode es su propia imagen, y un perfil fijado a `26.4.1` siempre se ejecuta en la imagen construida con Xcode 26.4.1. Para ejecutar dos versiones de Xcode, crea un perfil para cada una.

## macOS {#macos}

Los runners de macOS son máquinas virtuales Apple silicon (arm64) que ejecutan **macOS 26 Tahoe** o **macOS 27 Golden Gate**, según indique el **Sistema operativo** del perfil. Los perfiles creados antes de que existiera esta opción se ejecutan en Tahoe. Cada Xcode se construye por separado para cada release de macOS, por lo que las versiones de Xcode que puede elegir un perfil dependen de su sistema operativo. El nombre de un runner incluye la versión exacta de macOS, por ejemplo `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`, y aparece en el paso **Configurar trabajo** del trabajo.

### Xcode {#xcode}

Cada imagen contiene **exactamente un Xcode**, que se selecciona con `xcode-select`, de modo que `xcodebuild` y `xcrun` lo usan sin un paso de configuración. Esta es la principal diferencia respecto a las imágenes alojadas en GitHub, que incluyen varias versiones de Xcode para alternar entre ellas durante el trabajo. Versiones disponibles:

{{runner_macos_xcode_versions}}

- **Ruta.** Xcode está en `/Applications/Xcode_<version>.app`. Para una versión con componente de parche, `/Applications/Xcode_<major>.<minor>.app` apunta al mismo bundle, de modo que `Xcode_26.4.app` resuelve a `Xcode_26.4.1.app`. Los flujos que codifican una ruta estilo GitHub o llaman a `xcode-select -s` con ella siguen funcionando.
- **Simuladores.** Los entornos de ejecución de simulador de iOS, tvOS, watchOS y visionOS que vienen con ese Xcode se descargan en la imagen, así que la primera `xcodebuild test` no tiene que obtenerlos.
- **Cadena de herramientas de Metal.** Desde Xcode 26, el compilador de Metal no viene incluido con Xcode y hay que descargarlo por separado. Cada imagen incluye la cadena de herramientas de Metal que corresponde a su Xcode, instalada para el usuario con el que se ejecutan los trabajos, de modo que `xcrun metal` y los proyectos con fuentes `.metal` compilan sin ejecutar `xcodebuild -downloadComponent MetalToolchain`.
- **Betas.** Los perfiles beta (por ejemplo `27.3-beta`) siguen la última beta de esa release. Cuando Apple publica una nueva beta, la imagen se reconstruye y el perfil pasa a ella sin cambios por tu parte.

### Software preinstalado {#macos-software}

- **Herramientas de Apple:** Xcode (una por imagen), entornos de ejecución de simulador, cadena de herramientas de Metal, `xcodes`, `xcbeautify`
- **Herramientas de Swift e iOS:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **Dispositivos:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **Lenguajes y entornos de ejecución:** Ruby mediante `rbenv` (2.7 y las dos últimas releases 3.x, la más reciente como predeterminada) con Bundler, Node.js 24 con npm, Yarn y pnpm, Go, Java 21 (Temurin, configurado como `JAVA_HOME`)
- **Gestores de paquetes y versiones:** Homebrew, mise
- **Control de versiones:** Git, Git LFS, Git Credential Manager, GitHub CLI (`gh`)
- **Utilidades:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **Agentes de CI:** GitHub Actions runner, Buildkite agent, Bitrise agent y CLI, GitLab job executor
- **Otros:** Rosetta 2, `safaridriver` habilitado

Las versiones de las herramientas provienen de Homebrew cuando se construye la imagen, y las imágenes se reconstruyen con regularidad. Para ver la versión exacta en un runner, imprímela en un paso, por ejemplo `swiftlint version` o `xcodebuild -version`.

### Entorno {#macos-environment}

- **Usuario y rutas.** Los trabajos se ejecutan como `runner`, con home `/Users/runner` y workspace `/Users/runner/work`, las mismas rutas que los runners alojados en GitHub, por lo que las acciones que las codifican funcionan.
- **`sudo`.** Sin contraseña. La VM pertenece exclusivamente a tu trabajo.
- **Homebrew.** El prefijo (`/opt/homebrew`) es propiedad de `runner`, así que `brew install <formula>` funciona sin `sudo`. `HOMEBREW_NO_AUTO_UPDATE` está establecido.
- **Shell.** Los pasos se ejecutan en un shell de login, por lo que Homebrew, `rbenv` y Node.js están en `PATH`. `LANG` es `en_US.UTF-8`.
- **`ImageOS`** es `macos26`, como en los runners alojados en GitHub, para que las acciones de configuración elijan binarios precompilados por él.
- **Certificados.** Los certificados intermedios WWDR (G3) y Developer ID (G2) de Apple están en el almacén de confianza del sistema para firma y notorización.
- **Permisos de privacidad.** Se conceden de antemano dos aprobaciones de privacidad de macOS, como en las imágenes alojadas en GitHub: scripting de Finder mediante Apple Events, que necesitan `create-dmg` y `osascript`, y el acceso del Simulador de iOS al micrófono, que necesitan las apps que graban audio en tests de UI. Los permisos dentro de un simulador, como `simctl privacy`, siguen siendo responsabilidad de tu trabajo.
- **Disco.** Cada trabajo comienza con al menos 100 GB de espacio libre en disco.

### No incluido {#macos-not-included}

- **La CLI de Tuist.** Instálala en el trabajo, por ejemplo con mise, para que tu proyecto controle la versión.
- **Otras versiones de Xcode.** Usa un perfil por versión de Xcode en lugar de `xcode-select`.
- **Docker.** Los runners de macOS no tienen demonio de Docker. Usa un perfil de Linux; consulta <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>.
- **Cadenas de herramientas que GitHub incluye en macOS** y que las compilaciones para iOS rara vez necesitan, como otras versiones de Java, el SDK de Android, .NET, Rust, versiones de Python o navegadores. Instálalas en un paso con Homebrew, mise o una acción de configuración.

## Linux {#linux}

Los runners de Linux son máquinas virtuales x86_64 (amd64) con **Ubuntu 24.04** o **Ubuntu 22.04**, elegidas por el perfil. Consulta <.localized_link href="/guides/features/runners/profiles#linux">Perfiles</.localized_link> para saber cómo elegir una versión.

### Software preinstalado {#linux-software}

- **Cadena de herramientas de compilación:** `build-essential` (GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **Cabeceras de desarrollo:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** Python 3 con `pip` y `venv` (la versión de la release de Ubuntu)
- **Contenedores:** Docker CLI con Buildx y Compose; el demonio se ejecuta junto al trabajo (consulta <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>)
- **Kubernetes:** `kubectl`, Helm
- **Android:** Android SDK en `/usr/local/lib/android/sdk` con herramientas de línea de comandos, platform-tools y todas las releases de plataformas y build-tools desde la API 34 en adelante, con licencias aceptadas
- **Control de versiones:** Git, Git LFS, cliente OpenSSH, GitHub CLI (`gh`)
- **Clientes de bases de datos:** PostgreSQL, MariaDB, Redis (`redis-cli`), SQLite
- **Archivos:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **Utilidades:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **Agentes de CI:** GitHub Actions runner, Buildkite agent, Bitrise agent y CLI, GitLab job executor

### Entorno {#linux-environment}

- **Usuario y rutas.** Los trabajos se ejecutan como `runner` (UID 1000) con home `/home/runner`, en el grupo `docker`, con `sudo` sin contraseña.
- **`ImageOS`** es `ubuntu24` o `ubuntu22`, coincidiendo con los runners alojados en GitHub.
- **Android.** `ANDROID_HOME` y `ANDROID_SDK_ROOT` apuntan al SDK. El emulador no está preinstalado; consulta <.localized_link href="/guides/features/runners#android-emulators">Emuladores de Android</.localized_link>.
- **Idioma.** `LANG` y `LC_ALL` son `C.UTF-8`, y `DEBIAN_FRONTEND` es `noninteractive`, así que `sudo apt-get install` no solicita interacción.

### No incluido {#linux-not-included}

La imagen de Linux cubre lo básico de la compilación en lugar de cada cadena de herramientas de lenguaje que GitHub preinstala. Instala lo que tu trabajo necesite con las acciones de configuración habituales (`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), con mise o con `apt-get`:

- **Runtimes de lenguajes** como Java, Node.js, Go, Ruby, .NET y Rust.
- **El NDK de Android.** Instala la versión que necesites con `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"`. `ANDROID_NDK_HOME` se deja sin establecer para que la compilación falle claramente en lugar de apuntar a un NDK que no existe.
- **Navegadores** y CLIs de nube distintos de `kubectl`, Helm y `gh`.

Para mantener una cadena de herramientas entre trabajos en lugar de instalarla cada vez, colócala en un <.localized_link href="/guides/features/runners/cache-volumes">volumen de caché</.localized_link>.

## Actualizaciones de imágenes {#image-updates}

Las imágenes se reconstruyen cuando Apple publica una nueva versión de Xcode o una beta, cuando se actualizan los agentes de CI y cuando modificamos las propias imágenes. Un trabajo siempre se ejecuta sobre una imagen completa y probada: las nuevas imágenes se despliegan gradualmente en la flota y nunca cambian mientras un trabajo está en ejecución.

Si falta una herramienta en la que dependa tu flujo de trabajo, [contáctanos](mailto:contact@tuist.dev) o pregunta en el [Slack de la comunidad](https://slack.tuist.dev).
