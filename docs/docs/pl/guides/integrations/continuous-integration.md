---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# Ciągła integracja (CI) {#continuous-integration-ci}

Aby uruchamiać polecenia Tuist w przepływach pracy [ciągłej
integracji](https://en.wikipedia.org/wiki/Continuous_integration), należy
zainstalować je w środowisku CI.

Uwierzytelnianie jest opcjonalne, ale wymagane, jeśli chcesz korzystać z funkcji
po stronie serwera, takich jak
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink>.

Poniższe sekcje zawierają przykłady, jak to zrobić na różnych platformach CI.

## Przykłady {#examples}

### Działania GitHub {#github-actions}

W [GitHub Actions](https://docs.github.com/en/actions) możesz użyć
<LocalizedLink href="/guides/server/authentication#oidc-tokens"> uwierzytelniania OIDC</LocalizedLink> do bezpiecznego, niejawnego
uwierzytelniania:

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

::: info OIDC SETUP
<!-- -->
Przed użyciem uwierzytelniania OIDC należy
<LocalizedLink href="/guides/integrations/gitforge/github"> połączyć repozytorium GitHub</LocalizedLink> z projektem Tuist. Uprawnienia `: id-token:
write` są wymagane do działania OIDC. Alternatywnie, można użyć
<LocalizedLink href="/guides/server/authentication#project-tokens"> tokenu projektu</LocalizedLink> z `TUIST_TOKEN` secret.
<!-- -->
:::

::: napiwek
<!-- -->
Zalecamy użycie `mise use --pin` w projektach Tuist, aby przypiąć wersję Tuist w
różnych środowiskach. Polecenie utworzy plik `.tool-versions` zawierający wersję
Tuist.
<!-- -->
:::

### Xcode Cloud {#xcode-cloud}

W [Xcode Cloud](https://developer.apple.com/xcode-cloud/), który używa projektów
Xcode jako źródła prawdy, musisz dodać skrypt
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script),
aby zainstalować Tuist i uruchomić potrzebne polecenia, na przykład `tuist
generate`:

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

::: info AUTHENTICATION
<!-- -->
Użyj tokenu
<LocalizedLink href="/guides/server/authentication#project-tokens">projektu</LocalizedLink>,
ustawiając zmienną środowiskową `TUIST_TOKEN` w ustawieniach przepływu pracy
Xcode Cloud.
<!-- -->
:::

### CircleCI {#circleci}

W [CircleCI](https://circleci.com) można używać
<LocalizedLink href="/guides/server/authentication#oidc-tokens"> uwierzytelniania OIDC</LocalizedLink> do bezpiecznego, niejawnego
uwierzytelniania:

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

::: info AUTHENTICATION
<!-- -->
Przed użyciem uwierzytelniania OIDC należy
<LocalizedLink href="/guides/integrations/gitforge/github"> połączyć repozytorium GitHub</LocalizedLink> z projektem Tuist. Tokeny CircleCI OIDC
zawierają podłączone repozytorium GitHub, którego Tuist używa do autoryzacji
dostępu do projektów. Alternatywnie można użyć
<LocalizedLink href="/guides/server/authentication#project-tokens"> tokenu projektu</LocalizedLink> ze zmienną środowiskową `TUIST_TOKEN`.
<!-- -->
:::

### Bitrise {#bitrise}

W [Bitrise](https://bitrise.io) można używać
<LocalizedLink href="/guides/server/authentication#oidc-tokens"> uwierzytelniania OIDC</LocalizedLink> do bezpiecznego, niejawnego
uwierzytelniania:

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

::: info AUTHENTICATION
<!-- -->
Przed użyciem uwierzytelniania OIDC należy
<LocalizedLink href="/guides/integrations/gitforge/github"> połączyć repozytorium GitHub</LocalizedLink> z projektem Tuist. Tokeny Bitrise OIDC
zawierają podłączone repozytorium GitHub, którego Tuist używa do autoryzacji
dostępu do projektów. Alternatywnie można użyć
<LocalizedLink href="/guides/server/authentication#project-tokens"> tokenu projektu</LocalizedLink> ze zmienną środowiskową `TUIST_TOKEN`.
<!-- -->
:::

### Codemagic {#codemagic}

W [Codemagic](https://codemagic.io) można dodać dodatkowy krok do przepływu
pracy, aby zainstalować Tuist:

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

::: info AUTHENTICATION
<!-- -->
Utwórz
<LocalizedLink href="/guides/server/authentication#project-tokens">project token</LocalizedLink> i dodaj go jako tajną zmienną środowiskową o nazwie
`TUIST_TOKEN`.
<!-- -->
:::
