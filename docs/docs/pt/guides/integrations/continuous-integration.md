---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# Integração contínua (CI) {#continuous-integration-ci}

Pode utilizar o Tuist em ambientes de [integração
contínua](https://en.wikipedia.org/wiki/Continuous_integration). As secções
seguintes fornecem exemplos de como fazer isto em diferentes plataformas de CI.

## Exemplos {#examples}

Para executar comandos Tuist em seus fluxos de trabalho de CI, você precisará
instalá-lo em seu ambiente de CI.

### Nuvem do Xcode {#xcode-cloud}

No [Xcode Cloud](https://developer.apple.com/xcode-cloud/), que utiliza
projectos Xcode como fonte de verdade, será necessário adicionar um script
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
para instalar o Tuist e executar os comandos necessários, por exemplo `tuist
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

Em [Codemagic](https://codemagic.io), pode acrescentar um passo adicional ao seu
fluxo de trabalho para instalar o Tuist:

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

### GitHub Actions {#github-actions}

Em [GitHub Actions](https://docs.github.com/en/actions) pode adicionar um passo
adicional para instalar o Tuist, e no caso de gerir a instalação do Mise, pode
utilizar a [mise-action](https://github.com/jdx/mise-action), que abstrai a
instalação do Mise e do Tuist:

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

::: dica Recomendamos o uso do comando `mise use --pin` em seus projetos Tuist
para fixar a versão do Tuist em todos os ambientes. O comando criará um arquivo
`.tool-versions` contendo a versão do Tuist. :::

## Autenticação {#authentication}

Ao usar recursos do lado do servidor, como
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink>, você
precisará de uma maneira de autenticar solicitações que vão dos seus fluxos de
trabalho de CI para o servidor. Para isso, você pode gerar um token com escopo
de projeto executando o seguinte comando:

```bash
tuist project tokens create my-handle/MyApp
```

O comando irá gerar um token para o projeto com o identificador completo
`my-account/my-project`. Defina o valor para a variável de ambiente
`TUIST_CONFIG_TOKEN` no seu ambiente de CI assegurando que está configurado como
um segredo para que não seja exposto.

> [IMPORTANTE] DETECÇÃO DO AMBIENTE DE CI O Tuist apenas utiliza o token quando
> detecta que está a ser executado num ambiente de CI. Se o seu ambiente de CI
> não for detectado, pode forçar a utilização do token definindo a variável de
> ambiente `CI` para `1`.
