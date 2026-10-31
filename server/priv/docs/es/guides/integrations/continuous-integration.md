---
{
  "title": "Integración continua (CI)",
  "titleTemplate": ":title · Automatización · Guías · Tuist",
  "description": "Aprende a usar Tuist en tus flujos de trabajo de CI."
}
---
# Integración continua (CI) {#continuous-integration-ci}

Para ejecutar comandos de Tuist en tus flujos de trabajo de [integración continua](https://en.wikipedia.org/wiki/Continuous_integration), deberás instalarlo en tu entorno de CI. 

La autenticación es opcional, pero necesaria si quieres usar funcionalidades del servidor como la <.localized_link href="/guides/features/cache">caché</.localized_link>. 

Las siguientes secciones ofrecen ejemplos de cómo hacerlo en distintas plataformas de CI.

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
      - run: tuist auth login
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
      - run: tuist auth login
      - run: tuist setup cache
```
```yaml [Project token (Mise)]
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
```yaml [Project token (Homebrew)]
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
> Antes de usar la autenticación OIDC, debes <.localized_link href="/guides/integrations/gitforge/github">conectar tu repositorio de GitHub</.localized_link> a tu proyecto de Tuist. Se requiere `permissions: id-token: write` para que OIDC funcione. Como alternativa, puedes usar un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el secreto `TUIST_TOKEN`.


> [!TIP]
> Recomendamos usar `mise use --pin` en tus proyectos de Tuist para fijar la versión de Tuist entre entornos. El comando creará un archivo `.tool-versions` con la versión de Tuist.


### Xcode Cloud {#xcode-cloud}

En [Xcode Cloud](https://developer.apple.com/xcode-cloud/), que usa los proyectos de Xcode como fuente de verdad, tendrás que añadir un script [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) para instalar Tuist y ejecutar los comandos que necesites, por ejemplo `tuist generate`:

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from .mise.toml

# Runs the version of Tuist indicated in the .mise.toml file {#runs-the-version-of-tuist-indicated-in-the-misetoml-file}
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
> Usa un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> configurando la variable de entorno `TUIST_TOKEN` en la configuración de tu flujo de trabajo de Xcode Cloud.


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
          name: Authenticate
          command: mise exec -- tuist auth login
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
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
> Antes de usar la autenticación OIDC, debes <.localized_link href="/guides/integrations/gitforge/github">conectar tu repositorio de GitHub</.localized_link> a tu proyecto de Tuist. Los tokens OIDC de CircleCI incluyen tu repositorio de GitHub conectado, que Tuist usa para autorizar el acceso a tus proyectos. Como alternativa, puedes usar un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con la variable de entorno `TUIST_TOKEN`.


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
          title: Authenticate
          inputs:
            - content: mise exec -- tuist auth login
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
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
> Antes de usar la autenticación OIDC, debes <.localized_link href="/guides/integrations/gitforge/github">conectar tu repositorio de GitHub</.localized_link> a tu proyecto de Tuist. Los tokens OIDC de Bitrise incluyen tu repositorio de GitHub conectado, que Tuist usa para autorizar el acceso a tus proyectos. Como alternativa, puedes usar un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con la variable de entorno `TUIST_TOKEN`.


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
          mise install # Installs the version from .mise.toml
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

En [Appcircle](https://appcircle.io), puedes usar los pasos de flujo de trabajo integrados [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) y [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands), o añadir un paso de **Custom Script** después del paso **Git Clone** para instalar Tuist por tu cuenta:

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
> El paso Tuist Install instala Tuist con Homebrew y ejecuta `tuist generate`. Configura la entrada **Tuist Version** para fijar la versión y luego añade un paso Tuist Commands para ejecutar comandos como `tuist test` o `tuist build`.

> [!NOTE]
> **Autenticación**
>
> Crea un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link>, añádelo como variable llamada `TUIST_TOKEN` a un [grupo de variables de entorno](https://docs.appcircle.io/build/build-environment-variables) y selecciona ese grupo en la configuración de tu compilación. Marca la variable como secreta con el icono del candado.

## Informe de ejecución {#run-report}

Cuando Tuist sube una ejecución, las URL del panel para esa ejecución se imprimen en los registros. Para obtenerlas sin analizar los registros —por ejemplo, para publicar el enlace al informe de pruebas en Slack cuando falla un trabajo o para alimentar una ejecución en tus propias herramientas— pasa `--run-report-path` (o establece `TUIST_RUN_REPORT_PATH`) a `tuist test`, `tuist xcodebuild test` o `tuist xcodebuild build`. Tuist escribe un informe JSON en esa ruta una vez que la ejecución se ha subido:

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
| `runId` | cadena | El identificador único de la ejecución. |
| `status` | cadena | `"success"` o `"failure"`. |
| `runURL` | cadena | La URL del panel para la ejecución. Siempre presente. |
| `testRunURL` | cadena? | La URL del panel para la ejecución de tests, presente cuando el comando ejecutó tests. |
| `buildRunURL` | cadena? | La URL del panel para la ejecución de compilación, presente cuando el comando compiló. |
| `testRuns` | matriz | Resultados de tests por esquema: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` y `skippedTestModules`. Los recuentos de tests son casos de test, y `skippedTests` cuenta los que el paquete de resultados informa como omitidos. `skippedTestModules` cuenta los módulos de test que los <.localized_link href="/guides/features/selective-testing">tests selectivos</.localized_link> omitieron, y se omite cuando los tests selectivos no se aplicaron o la ejecución es un fragmento de test. |
| `buildRuns` | matriz | Resultados de compilación por esquema: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` y `buildRunURL` son independientes: un comando que tanto compila como ejecuta tests escribe ambas, algo que los registros no pueden hacer —solo imprimen una URL por ejecución.

> [!NOTE]
> **Cuándo se escribe el informe**
>
> El informe se escribe solo para las ejecuciones que se suben al servidor, lo cual requiere autenticación y ocurre automáticamente en CI. La ruta se limpia al inicio de cada ejecución, por lo que una ejecución que no genera ningún informe no deja nada atrás en lugar de dejar uno obsoleto de una ejecución anterior.

En GitLab CI, un uso común es exponer una URL a trabajos posteriores mediante un informe [`dotenv`](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv):

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
