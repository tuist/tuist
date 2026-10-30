---
{
  "title": "Volúmenes de caché",
  "titleTemplate": ":title · Runners · Funcionalidades · Guías · Tuist",
  "description": "Mantén las cachés de Xcode, de módulos y de Gradle, así como cualquier otro directorio, entre trabajos de runners de Linux o macOS de Tuist con GitHub Actions, Buildkite y GitLab CI."
}
---
# Volúmenes de caché {#cache-volumes}

Los runners de Tuist pueden mantener las cachés entre trabajos, de modo que un runner nuevo arranca en caliente. Cada trabajo recibe una copia privada y escribible del último contenido guardado.

- **Las cachés gestionadas** mantienen la caché de compilación de Xcode, la caché de módulos de Tuist y las cachés de Gradle con un solo paso cada una. Tuist sabe dónde reside cada caché y la conserva dentro de su almacenamiento.
- **Los volúmenes personalizados** mantienen cualquier otro directorio, como la caché de descargas de un gestor de paquetes, bajo una clave que tú elijas.

Añade los pasos después del checkout y antes de los comandos que usan las cachés. En runners que no son de Tuist no hacen nada, y un problema de caché nunca hace fallar el trabajo: el paso registra una advertencia y el trabajo continúa con una caché vacía.

## Cachés gestionadas {#managed-caches}

Los pasos solo deciden dónde residen las cachés. Mantén tu configuración de caché existente: `tuist setup cache` o los ajustes de compilación que activan la caché de compilación (consulta la <.localized_link href="/guides/features/cache/xcode-cache">guía de la caché de Xcode</.localized_link>), la autenticación para la caché de módulos y el <.localized_link href="/guides/features/cache/gradle-cache">plugin de Gradle de Tuist</.localized_link> para la caché remota de compilación de Gradle. En GitLab CI, combina fragmentos con `!reference`, porque `extends` reemplaza a `before_script`.

### Caché de Xcode {#xcode-cache}

Mantiene el almacén de la caché de compilación de Xcode en runners macOS.

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [Buildkite]
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```
<!-- -->
:::

### Caché de módulos {#module-cache}

Mantiene la caché local de Tuist en runners macOS: binarios de la <.localized_link href="/guides/features/cache/module-cache">caché de módulos</.localized_link>, manifiestos compilados, plugins y resultados de tests selectivos.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-macos
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - run: tuist auth login
      - run: tuist install
      - run: tuist generate --no-open
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist install
      tuist generate --no-open
      tuist test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist install
    - tuist generate --no-open
    - tuist test
```
<!-- -->
:::

### Caché de Gradle {#gradle-cache}

Mantiene los directorios `caches` y `wrapper` del home de usuario de Gradle en runners Linux y macOS: dependencias, jars transformados, scripts de compilación compilados y distribuciones de Gradle. Establece `GRADLE_USER_HOME` antes del paso si lo usas, y desactiva otras formas de caché para esos directorios, como `cache: gradle` en `actions/setup-java`.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/gradle-cache@v1
      - run: ./gradlew test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```
<!-- -->
:::

## Volúmenes personalizados {#custom-volumes}

Elige una `key` estable y una `path`, luego adjunta el volumen antes de instalar las dependencias. La ruta debe estar vacía o ausente. Elimina cualquier caché de archivo o restauración de artefactos que escriba en el mismo directorio. Para mantener varios directorios en un solo volumen, consulta [Varios directorios en un volumen](#several-directories-in-one-volume).

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: |
      npm ci
      npm test
```

```yaml [GitLab CI]
test:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - npm ci
    - npm test
```
<!-- -->
:::

### Varios directorios en un volumen {#several-directories-in-one-volume}

Un volumen puede contener varios directorios. En GitHub Actions, lista una ruta por línea; en Buildkite, establece `path` como una lista; en GitLab CI, pasa `--path` una vez por directorio. Las líneas en blanco y los espacios circundantes se ignoran.

::: code-group

```yaml [GitHub Actions]
jobs:
  lint:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: python-tools
          path: |
            ~/.cache/pip
            ~/.cache/pre-commit
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

```yaml [Buildkite]
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: |
      pip install pre-commit
      pre-commit run --all-files
```

```yaml [GitLab CI]
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```
<!-- -->
:::

- **Capacidad compartida.** Todas las rutas comparten la capacidad del volumen y se restauran y guardan juntas.
- **Agrupa directorios pequeños y relacionados.** Asigna su propio volumen a un directorio grande o que cambia con frecuencia.
- **Sin anidamiento.** Las rutas de un volumen no deben contenerse entre sí.
- **Cambiar la lista empieza en frío.** Cada ruta se almacena en su propio directorio dentro del volumen, identificado por cómo está escrita la ruta. Cambiar entre una ruta y varias, o añadir, eliminar o reescribir una ruta, modifica esa disposición: el primer trabajo tras el cambio arranca en frío para las rutas afectadas. El contenido de las rutas que ya no aparecen en la lista permanece en el volumen hasta que lo limpies.

### Cómo funcionan las claves {#how-keys-work}

Una clave nombra un volumen que cambia con el tiempo; no es el nombre de una instantánea fija como una clave de `actions/cache`.

- **Un volumen por clave.** Cada clave tiene alcance al repositorio (en Buildkite, la pipeline; en GitLab CI, el proyecto), plataforma, arquitectura de CPU y usuario. Cada trabajo que la adjunta arranca desde el último contenido guardado, y los trabajos elegibles guardan sus cambios de vuelta en el mismo volumen.
- **Mantén las claves estables.** No incluyas versiones ni hashes de archivos de bloqueo en una clave. Con `actions/cache`, una clave como `deps-${{ hashFiles('Package.resolved') }}` crea una nueva entrada por cada cambio, y `restore-keys` recurre a una anterior. Aquí, una clave nueva es un volumen nuevo y vacío: el primer trabajo tras cada cambio arranca en frío, y los volúmenes antiguos permanecen hasta que caducan. Mantén la clave y deja que tu herramienta actualice el contenido; los gestores de paquetes reutilizan lo que siga siendo válido.
- **Sin coincidencias parciales.** No hay claves de restauración. Una clave que aún no se ha guardado arranca vacía.
- **Reinicia a propósito.** Cambia la clave o limpia el volumen en el dashboard cuando quieras que un trabajo arranque vacío.
- **Deja las claves `tuist-` a Tuist.** Las cachés gestionadas usan claves que empiezan por `tuist-`, así que elige un nombre distinto para tus propios volúmenes.

En Linux, las rutas se montan como directorios normales, por lo que las herramientas pueden usar sus ubicaciones habituales como `deps`, `_build` y `node_modules`. Mantén tus reglas normales de `.gitignore`. En macOS, las rutas son enlaces simbólicos: usa cachés de descarga como `~/.npm`; `node_modules` y las herramientas que reemplazan su directorio de caché no son compatibles. Ignora los enlaces de workspace sin barra final en `.gitignore`.

## Guardar cambios {#saving-changes}

Las cachés gestionadas y los volúmenes personalizados guardan los cambios de los trabajos exitosos de tu propio repositorio, en cualquier rama:

| Proveedor | Trabajos que guardan cambios |
| --- | --- |
| GitHub Actions | Trabajos de push, programados, de dispatch manual y de pull request del propio repositorio |
| Buildkite | Compilaciones por webhook y programadas del repositorio de la pipeline, incluidas sus pull requests |
| GitLab CI | Pipelines de push, programadas y web del proyecto, y pipelines de sus propias merge requests cuando la conexión tiene un <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">token de acceso a la API</.localized_link> |

Otros trabajos pueden usar la caché, pero sus cambios se descartan. Esto incluye pull requests de forks, trabajos de `pull_request_target`, compilaciones de Buildkite iniciadas desde la API o el dashboard, merge requests de GitLab desde forks o sin token de acceso a la API, y etiquetas. Un trabajo que no cambia un volumen deja la versión guardada intacta. Puedes restringir qué ramas guardan en el perfil del runner; consulta [Elegir qué ramas guardan](#choose-which-branches-save).

Los trabajos concurrentes funcionan de forma independiente; los cambios de distintos trabajos no se fusionan. Nunca almacenes en caché credenciales ni datos irremplazables.

### Elegir qué ramas guardan {#choose-which-branches-save}

Puedes cambiar qué ramas guardan las cachés gestionadas y los volúmenes personalizados. Abre **Runners → Profiles**, edita el perfil que usan tus trabajos y expande **Save cache from**. Los trabajos usan el perfil que solicitan: en `runs-on:` en GitHub Actions, como cola en Buildkite o en `tags:` en GitLab CI. La configuración se aplica a todos los volúmenes que usen los trabajos de ese perfil, incluidos los creados posteriormente.

![El formulario de perfil de runner con la sección Save cache from expandida, con Default branch activada y develop y release/* añadidas como ramas adicionales](/images/guides/features/runners/save-cache-from.png)

De forma predeterminada, cada trabajo exitoso del repositorio guarda sus cambios. Para guardar solo desde algunas ramas, activa **Limit to specific branches**:

- **Default branch** permite que los trabajos en la rama predeterminada de cada repositorio guarden. Desactívala para guardar solo desde las ramas adicionales.
- En **Additional branches**, añade hasta 20 nombres de rama que también guarden. Usa `*` como comodín: `release/*` coincide con `release/1.0`.

Los trabajos listados en [Guardar cambios](#saving-changes) guardan sus cambios cuando su rama coincide. En ejecuciones de push y dispatch manual de GitHub Actions, una etiqueta con un nombre coincidente también coincide.

Los trabajos en otras ramas aún pueden usar la caché, pero sus cambios se descartan. Los trabajos que nunca guardan, como las pull requests de forks, tampoco guardan en una rama coincidente. Restringir esta configuración o eliminar el perfil descarta los cambios pendientes que ya no permiten; un perfil eliminado vuelve a guardar desde todas las ramas.

## Capacidad y retención {#capacity-and-retention}

La caché de Xcode comienza con **30 GB**. La caché de módulos, la caché de Gradle y cada volumen personalizado comienzan con **20 GB**. Establece un tamaño para dar a una caché o volumen otra capacidad, un número entero de GB entre `1gb` y `100gb`:

::: code-group

```yaml [GitHub Actions]
- uses: tuist/xcode-cache@v1
  with:
    size: 50gb
- uses: tuist/module-cache@v1
  with:
    size: 40gb
```

```yaml [Buildkite]
plugins:
  - tuist/xcode-cache#v1:
      size: 50gb
  - tuist/module-cache#v1:
      size: 40gb
```

```yaml [GitLab CI]
build:
  variables:
    TUIST_XCODE_CACHE_SIZE: 50gb
    TUIST_MODULE_CACHE_SIZE: 40gb
```
<!-- -->
:::

La caché de Gradle y los volúmenes personalizados aceptan la misma entrada `size` (`TUIST_GRADLE_CACHE_SIZE` y `TUIST_VOLUME_SIZE` en GitLab CI, `--size` para `tuist-cache-volume`). Un tamaño mayor aumenta el volumen, conservando su contenido, a partir del siguiente trabajo. Un tamaño menor se aplica después de que el volumen se limpie o caduque la próxima vez. Cuando los trabajos solicitan distintos tamaños para una misma caché, se aplica el mayor, así que declara cada tamaño en un único lugar.

Todas caducan tras **7 días sin montaje por un trabajo**, y el siguiente trabajo comienza con un volumen vacío después de la caducidad. Tuist poda las cachés de Xcode y de módulos para ajustarse a su capacidad, y el paso de la caché de Gradle hace que Gradle elimine las entradas no utilizadas durante siete días después de cada compilación.

Los volúmenes personalizados no podan dependencias antiguas: usa la configuración de limpieza de tu herramienta para mantenerlos pequeños. Las escrituras en un volumen lleno pueden hacer fallar el trabajo. Cuando el contenido guardado alcanza el **80%** de la capacidad del volumen y un trabajo se queda sin espacio en él, el siguiente trabajo comienza con un volumen vacío y sus cambios inician un nuevo estado guardado.

## Inspeccionar y limpiar volúmenes {#inspecting-and-clearing-volumes}

Abre **Runners → Volumes** para inspeccionar el espacio usado, la tasa de aciertos de caché y el historial de trabajos. Los administradores de cuenta pueden seleccionar **Clear volume** para que los futuros trabajos comiencen vacíos. Los trabajos en ejecución conservan sus copias privadas pero no pueden guardarlas de vuelta. Las cachés de Xcode y de módulos también aparecen allí, pero no se pueden limpiar.
