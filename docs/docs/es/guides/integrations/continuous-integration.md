---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# Integración continua (IC) {#continuous-integration-ci}

Puedes utilizar Tuist en entornos de [integración
continua](https://en.wikipedia.org/wiki/Continuous_integration). Las siguientes
secciones proporcionan ejemplos de cómo hacerlo en diferentes plataformas CI.

## Ejemplos {#examples}

Para ejecutar comandos Tuist en sus flujos de trabajo CI, necesitará instalarlo
en su entorno CI.

### Xcode Cloud {#xcode-cloud}

En [Xcode Cloud](https://developer.apple.com/xcode-cloud/), que utiliza los
proyectos de Xcode como fuente de verdad, tendrás que añadir un script
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
para instalar Tuist y ejecutar los comandos que necesites, por ejemplo `tuist
generate`:

:::grupo de códigos

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
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
:::
### Codemagic {#codemagic}

En [Codemagic](https://codemagic.io), puedes añadir un paso adicional a tu flujo
de trabajo para instalar Tuist:

::: grupo de códigos
```yaml [Mise]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from .mise.toml
      - name: Build
        script: mise exec -- tuist build
```
```yaml [Homebrew]
workflows:
  lint:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist build
```
:::

### Acciones de GitHub {#github-actions}

En [GitHub Actions](https://docs.github.com/en/actions) puedes añadir un paso
adicional para instalar Tuist, y en el caso de gestionar la instalación de Mise,
puedes utilizar la [mise-action](https://github.com/jdx/mise-action), que
abstrae la instalación de Mise y Tuist:

::: grupo de códigos
```yaml [Mise]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: jdx/mise-action@v2
      - run: tuist build
```
```yaml [Homebrew]
name: test
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
jobs:
  lint:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - run: brew install --formula tuist@x.y.z
      - run: tuist build
```
:::

::: consejo Recomendamos usar `mise use --pin` en tus proyectos Tuist para
anclar la versión de Tuist entre entornos. El comando creará un archivo
`.tool-versions` que contendrá la versión de Tuist. :::

## Autenticación {#authentication}

Al utilizar funciones del lado del servidor como
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink>, necesitará
una forma de autenticar las solicitudes que van desde sus flujos de trabajo de
CI al servidor. Para ello, puede generar un token de proyecto ejecutando el
siguiente comando:

```bash
tuist project tokens create my-handle/MyApp
```

El comando generará un token para el proyecto con el nombre completo
`my-account/my-project`. Establece el valor de la variable de entorno
`TUIST_CONFIG_TOKEN` en tu entorno CI asegurándote de que está configurado como
secreto para que no quede expuesto.

> [IMPORTANTE] DETECCIÓN DE ENTORNO CI Tuist sólo utiliza el token cuando
> detecta que se está ejecutando en un entorno CI. Si tu entorno CI no es
> detectado, puedes forzar el uso del token estableciendo la variable de entorno
> `CI` a `1`.
