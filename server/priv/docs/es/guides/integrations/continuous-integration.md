---
{
  "title": "Integración continua (CI)",
  "titleTemplate": ":title · Automatizar · Guías · Tuist",
  "description": "Aprende a usar Tuist en tus flujos de trabajo de CI."
}
---
# Integración continua (CI) {#continuous-integration-ci}

Para ejecutar comandos de Tuist en tus flujos de trabajo de [integración continua](https://en.wikipedia.org/wiki/Continuous_integration), debes instalarlo en tu entorno de CI. 

La autenticación es opcional, pero necesaria si quieres usar funcionalidades del servidor como la <.localized_link href="/guides/features/cache">caché</.localized_link>. Para reducir la duración y el coste de las ejecuciones de CI una vez instalado Tuist, consulta [Compilaciones lentas](https://tuist.dev/solutions/slow-builds) y [Costes de CI](https://tuist.dev/solutions/ci-costs).

Las siguientes secciones muestran ejemplos de cómo hacerlo en distintas plataformas de CI. Once se conecta a través de su propio proveedor nativo de Tuist; no necesita la CLI de Tuist. Consulta [Once](#once) para ese flujo de trabajo.

## Once {#once}

Confirma el proveedor y la vinculación de caché desde <.localized_link href="/guides/get-started/once-project">Comienza con Once</.localized_link>. Instala Once en el job siguiendo las [instrucciones de instalación de Once](https://buildonce.dev/docs/guide/getting-started) y autentícate antes de ejecutar trabajos que puedan usar la caché.

GitHub Actions, CircleCI y Bitrise admiten el inicio de sesión sin interfaz de OpenID Connect de Once. Conecta el repositorio a tu proyecto de Tuist como se describe en <.localized_link href="/guides/server/authentication#oidc-tokens">Autenticación OIDC</.localized_link>. En GitHub Actions, concede el permiso identity-token:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: jdx/mise-action@v2
      # Pin Once in your repository's mise.toml.
      - run: once auth login --provider tuist --no-browser
      - run: once build MyTarget
      - run: once test
```

Elige un sistema operativo con las toolchains que requieran tus targets. Sustituye `MyTarget` por tu target y fija la versión de Once mediante tu flujo de instalación de herramientas existente. La sesión resultante se reutiliza para acceder a la caché, generar informes y publicar artefactos durante el job.

En otros proveedores, asigna a `TUIST_TOKEN` un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> autorizado para las operaciones que necesites. Guárdalo en el almacén de secretos de CI, nunca en `once.toml` ni en el código fuente del flujo de trabajo. No se requiere ningún paso de inicio de sesión interactivo al usar ese token.

Para suites con varios workers, sigue la guía de <.localized_link href="/guides/features/test-sharding/once">Sharding de tests con Once</.localized_link>. Para publicar aplicaciones, añade un paso explícito de <.localized_link href="/guides/features/previews/once">Publicación de previews con Once</.localized_link>. Las compilaciones ordinarias no publican previews de forma implícita.

## Ejemplos {#examples}

### GitHub Actions {#github-actions}

En [GitHub Actions](https://docs.github.com/en/actions) puedes usar la <.localized_link href="/guides/server/authentication#oidc-tokens">autenticación OIDC</.localized_link> para una autenticación segura y sin secretos:

::: code-group
```yaml [OIDC (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist setup cache
```
```yaml [OIDC (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist setup cache
```
```yaml [Account token (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist setup cache
```
```yaml [Account token (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Configuración de OIDC**
>
> Antes de usar la autenticación OIDC, debes <.localized_link href="/guides/integrations/gitforge/github">conectar tu repositorio de GitHub</.localized_link> a tu proyecto de Tuist. El permiso `permissions: id-token: write` es necesario para que OIDC funcione. A partir de Tuist 4.218.0, la CLI intercambia el token de identidad en su primera solicitud, por lo que el flujo de trabajo no necesita el paso `tuist auth login`; en versiones anteriores, ejecuta `tuist auth login` antes de otros comandos de Tuist. Como alternativa, puedes usar un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el secreto `TUIST_TOKEN`.


> [!TIP]
> Recomendamos usar `mise use --pin` en tus proyectos de Tuist para fijar la versión de Tuist en todos los entornos. El comando fija la versión de Tuist en tu archivo `mise.toml`.


### Xcode Cloud {#xcode-cloud}

En [Xcode Cloud](https://developer.apple.com/xcode-cloud/), que usa proyectos de Xcode como fuente única de verdad, deberás añadir un script [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) para instalar Tuist y ejecutar los comandos que necesites, por ejemplo `tuist generate`:

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from mise.toml

# Runs the version of Tuist indicated in the mise.toml file
mise exec -- tuist install --path ../ # `--path` needed as this is run from within the `ci_scripts` directory
mise exec -- tuist generate -p ../ --no-open # `-p` needed as this is run from within the `ci_scripts` directory
```
```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```
<!-- -->
:::

> [!NOTE]
> **Autenticación**
>
> Usa un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> configurando la variable de entorno `TUIST_TOKEN` en la configuración del flujo de trabajo de Xcode Cloud.


### CircleCI {#circleci}

En [CircleCI](https://circleci.com) puedes usar la <.localized_link href="/guides/server/authentication#oidc-tokens">autenticación OIDC</.localized_link> para una autenticación segura y sin secretos:

::: code-group
```yaml [OIDC (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
```yaml [Account token (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    environment:
      TUIST_TOKEN: $TUIST_TOKEN
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Autenticación**
>
> Antes de usar la autenticación OIDC, debes <.localized_link href="/guides/integrations/gitforge/github">conectar tu repositorio de GitHub</.localized_link> a tu proyecto de Tuist. Los tokens OIDC de CircleCI incluyen tu repositorio de GitHub conectado, que Tuist utiliza para autorizar el acceso a tus proyectos. A partir de Tuist 4.218.0, la CLI intercambia el token de identidad en su primera solicitud, por lo que no es necesario el paso `tuist auth login`; en versiones anteriores, ejecuta `mise exec -- tuist auth login` antes de otros comandos de Tuist. Como alternativa, puedes usar un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con la variable de entorno `TUIST_TOKEN`.


### Bitrise {#bitrise}

En [Bitrise](https://bitrise.io) puedes usar la <.localized_link href="/guides/server/authentication#oidc-tokens">autenticación OIDC</.localized_link> para una autenticación segura y sin secretos:

::: code-group
```yaml [OIDC (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - get-identity-token@0:
          inputs:
          - audience: tuist
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
```yaml [Account token (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Autenticación**
>
> Antes de usar la autenticación OIDC, debes <.localized_link href="/guides/integrations/gitforge/github">conectar tu repositorio de GitHub</.localized_link> a tu proyecto de Tuist. Los tokens OIDC de Bitrise incluyen tu repositorio de GitHub conectado, que Tuist utiliza para autorizar el acceso a tus proyectos. A partir de Tuist 4.218.0, la CLI intercambia el token de identidad en su primera solicitud, por lo que no es necesario el paso `tuist auth login`; en versiones anteriores, ejecuta `mise exec -- tuist auth login` antes de otros comandos de Tuist. Como alternativa, puedes usar un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con la variable de entorno `TUIST_TOKEN`.


### Codemagic {#codemagic}

En [Codemagic](https://codemagic.io), puedes añadir un paso adicional a tu flujo de trabajo para instalar Tuist:

::: code-group
```yaml [Mise]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from mise.toml
      - name: Build
        script: mise exec -- tuist setup cache
```
```yaml [Homebrew]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Autenticación**
>
> Crea un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> y añádelo como variable de entorno secreta llamada `TUIST_TOKEN`.

### Appcircle {#appcircle}

En [Appcircle](https://appcircle.io), puedes usar los pasos de flujo de trabajo integrados [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) y [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands), o bien añadir un paso de **Custom Script** después del paso **Git Clone** para instalar Tuist tú mismo:

::: code-group
```bash [Mise]
cd $AC_REPOSITORY_DIR
curl https://mise.jdx.dev/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
mise install
mise exec -- tuist setup cache
```
```bash [Homebrew]
cd $AC_REPOSITORY_DIR
brew install --formula tuist@x.y.z
tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **Pasos del flujo de trabajo**
>
> El paso Tuist Install instala Tuist con Homebrew y ejecuta `tuist generate`. Configura la entrada **Tuist Version** para fijar la versión y, a continuación, añade un paso Tuist Commands para ejecutar comandos como `tuist test` o `tuist build`.

> [!NOTE]
> **Autenticación**
>
> Crea un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link>, añádelo como variable llamada `TUIST_TOKEN` a un [grupo de variables de entorno](https://docs.appcircle.io/build/build-environment-variables) y selecciona ese grupo en la configuración de compilación. Marca la variable como secreta con el icono del candado.

## Formato de salida de xcodebuild {#xcodebuild-output-formatting}

`tuist build`, `tuist test`, `tuist xcodebuild build` y `tuist xcodebuild test` formatean la salida de `xcodebuild` con el formateador de [xcbeautify](https://github.com/cpisciotta/xcbeautify), por lo que no necesitas canalizar estos comandos a través de xcbeautify tú mismo. En GitHub Actions, detectado mediante la variable de entorno `GITHUB_ACTIONS`, Tuist utiliza el renderizador de GitHub Actions de xcbeautify, que muestra advertencias del compilador, errores y fallos de tests como anotaciones en el resumen de la ejecución y en la pull request. En cualquier otro caso usa el renderizador de terminal, con color a menos que la salida esté canalizada o `NO_COLOR` esté configurada.

Pasa `--verbose` para imprimir la salida sin formato de `xcodebuild`, por ejemplo cuando una compilación falla sin un error claro.

Si un job llama a `xcodebuild` directamente en lugar de a través de Tuist, canalízalo tú mismo a través de xcbeautify y configura `pipefail` para que una compilación fallida siga haciendo fallar el paso:

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## Informe de ejecución {#run-report}

Cuando Tuist sube una ejecución, las URLs del panel para esa ejecución se imprimen en los registros. Para obtenerlas sin extraerlas de los registros —por ejemplo, para publicar el enlace al informe de tests en Slack cuando un job falla o para alimentar una ejecución en tus propias herramientas— pasa `--run-report-path` (o configura `TUIST_RUN_REPORT_PATH`) a `tuist test`, `tuist xcodebuild test` o `tuist xcodebuild build`. Tuist escribe un informe JSON en esa ruta una vez que la ejecución se ha subido:

```json
{
  "runId": "0193f8c1-...",
  "status": "success",
  "runURL": "https://tuist.dev/acme/app/runs/0193f8c1-...",
  "testRunURL": "https://tuist.dev/acme/app/tests/test-runs/...",
  "buildRunURL": "https://tuist.dev/acme/app/builds/build-runs/...",
  "testRuns": [
    {
      "scheme": "App",
      "succeeded": true,
      "totalTests": 42,
      "skippedTests": 0,
      "ranTests": 42,
      "failedTestNames": [],
      "ranTestModules": 3,
      "skippedTestModules": 5
    }
  ],
  "buildRuns": [
    { "scheme": "App", "succeeded": true, "durationInSeconds": 12.3 }
  ]
}
```

| Campo | Tipo | Descripción |
| - | - | - |
| `runId` | cadena | Identificador único de la ejecución. |
| `status` | cadena | `"success"` o `"failure"`. |
| `runURL` | cadena | URL del panel para la ejecución. Siempre presente. |
| `testRunURL` | cadena? | URL del panel para la ejecución de tests, presente cuando el comando ejecutó tests. |
| `buildRunURL` | cadena? | URL del panel para la ejecución de compilación, presente cuando el comando compiló. |
| `testRuns` | array | Resultados de tests por esquema: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` y `skippedTestModules`. Los recuentos de tests son casos de test, y `skippedTests` cuenta los que el paquete de resultados indica como omitidos. `skippedTestModules` cuenta los módulos de test que los <.localized_link href="/guides/features/selective-testing">tests selectivos</.localized_link> omitieron y se omite cuando los tests selectivos no se aplicaron o la ejecución es un fragmento de test. |
| `buildRuns` | array | Resultados de compilación por esquema: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` y `buildRunURL` son independientes: un comando que compila y ejecuta tests escribe ambas, algo que los registros no pueden hacer —solo imprimen una URL por ejecución.

> [!NOTE]
> **Cuándo se escribe el informe**
>
> El informe solo se escribe para las ejecuciones que se suben al servidor, lo cual requiere autenticación y ocurre automáticamente en CI. La ruta se limpia al inicio de cada ejecución, por lo que una ejecución que no genera informe no deja nada detrás en lugar de dejar uno obsoleto de una ejecución anterior.

En GitLab CI, un uso común es exponer una URL a jobs posteriores mediante un [informe `dotenv`](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv):

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
