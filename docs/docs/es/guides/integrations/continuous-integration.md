---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# Integración continua (CI) {#continuous-integration-ci}

Para ejecutar comandos Tuist en tus flujos de trabajo de [integración
continua](https://en.wikipedia.org/wiki/Continuous_integration), necesitarás
instalarlo en tu entorno CI.

La autenticación es opcional pero necesaria si desea utilizar funciones del lado
del servidor como
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink>.

Las siguientes secciones ofrecen ejemplos de cómo hacerlo en diferentes
plataformas CI.

## Ejemplos {#examples}

### Acciones de GitHub {#github-actions}

En [Acciones de GitHub](https://docs.github.com/en/actions) puedes utilizar
<LocalizedLink href="/guides/server/authentication#oidc-tokens">Autenticación OIDC</LocalizedLink> para una autenticación segura y sin secretos:

::: grupo de códigos
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

::: info OIDC SETUP
<!-- -->
Antes de usar la autenticación OIDC, necesitas
<LocalizedLink href="/guides/integrations/gitforge/github">conectar tu repositorio GitHub</LocalizedLink> a tu proyecto Tuist. Los permisos `:
id-token: write` son necesarios para que OIDC funcione. Alternativamente, puedes
usar un
<LocalizedLink href="/guides/server/authentication#project-tokens">project token</LocalizedLink> con el `TUIST_TOKEN` secreto.
<!-- -->
:::

::: consejo
<!-- -->
Recomendamos usar `mise use --pin` en tus proyectos Tuist para fijar la versión
de Tuist en todos los entornos. El comando creará un archivo `.tool-versions`
que contiene la versión de Tuist.
<!-- -->
:::

### Xcode en la nube {#xcode-cloud}

En [Xcode Cloud](https://developer.apple.com/xcode-cloud/), que utiliza los
proyectos de Xcode como fuente de verdad, tendrás que añadir un script
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
para instalar Tuist y ejecutar los comandos que necesites, por ejemplo `tuist
generate`:

::: grupo de códigos

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

::: info AUTHENTICATION
<!-- -->
Utilice un
token<LocalizedLink href="/guides/server/authentication#project-tokens">de proyecto</LocalizedLink> estableciendo la variable de entorno `TUIST_TOKEN` en
la configuración del flujo de trabajo de Xcode Cloud.
<!-- -->
:::

### CircleCI {#circleci}

En [CircleCI](https://circleci.com) puede utilizar
<LocalizedLink href="/guides/server/authentication#oidc-tokens">Autenticación OIDC</LocalizedLink> para una autenticación segura y sin secretos:

::: grupo de códigos
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

::: info AUTHENTICATION
<!-- -->
Antes de usar la autenticación OIDC, necesitas
<LocalizedLink href="/guides/integrations/gitforge/github">conectar tu repositorio GitHub</LocalizedLink> a tu proyecto Tuist. Los tokens OIDC de
CircleCI incluyen tu repositorio GitHub conectado, que Tuist utiliza para
autorizar el acceso a tus proyectos. Alternativamente, puedes utilizar un
<LocalizedLink href="/guides/server/authentication#project-tokens">project token</LocalizedLink> con la variable de entorno `TUIST_TOKEN`.
<!-- -->
:::

### Bitrise {#bitrise}

En [Bitrise](https://bitrise.io) puede utilizar
<LocalizedLink href="/guides/server/authentication#oidc-tokens">Autenticación OIDC</LocalizedLink> para una autenticación segura y sin secretos:

::: grupo de códigos
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

::: info AUTHENTICATION
<!-- -->
Antes de usar la autenticación OIDC, necesitas
<LocalizedLink href="/guides/integrations/gitforge/github">conectar tu repositorio GitHub</LocalizedLink> a tu proyecto Tuist. Los tokens OIDC de
Bitrise incluyen tu repositorio GitHub conectado, que Tuist utiliza para
autorizar el acceso a tus proyectos. Alternativamente, puedes usar un
<LocalizedLink href="/guides/server/authentication#project-tokens">project token</LocalizedLink> con la variable de entorno `TUIST_TOKEN`.
<!-- -->
:::

### Codemagic {#codemagic}

En [Codemagic](https://codemagic.io), puedes añadir un paso adicional a tu flujo
de trabajo para instalar Tuist:

::: grupo de códigos
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

::: info AUTHENTICATION
<!-- -->
Cree un
<LocalizedLink href="/guides/server/authentication#project-tokens">project token</LocalizedLink> y añádalo como variable de entorno secreta denominada
`TUIST_TOKEN`.
<!-- -->
:::
