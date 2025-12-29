---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 持續整合 (CI){#continuous-integration-ci}

若要在 [continuous
integration](https://en.wikipedia.org/wiki/Continuous_integration) 工作流程中執行 Tuist
指令，您需要在 CI 環境中安裝。

驗證是可選的，但如果您要使用
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink>
等伺服器端功能，則需要驗證。

以下各節將舉例說明如何在不同的 CI 平台上執行。

## 範例{#examples}

### GitHub 動作{#github-actions}

在 [GitHub Actions](https://docs.github.com/en/actions) 上，您可以使用
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
認證</LocalizedLink> 來進行安全的無密認證：

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
Before using OIDC authentication, you need to
<LocalizedLink href="/guides/integrations/gitforge/github">connect your GitHub
repository</LocalizedLink> to your Tuist project. The `permissions: id-token:
write` is required for OIDC to work. Alternatively, you can use an
<LocalizedLink href="/guides/server/authentication#account-tokens">account
token</LocalizedLink> with the `TUIST_TOKEN` secret.
<!-- -->
:::

::: tip
<!-- -->
我們建議在您的 Tuist 專案中使用`mise use --pin` 來釘住跨環境的 Tuist 版本。該指令會建立`.tool-versions`
檔案，其中包含 Tuist 的版本。
<!-- -->
:::

### Xcode 雲端{#xcode-cloud}

在使用 Xcode 專案作為真相來源的 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)
中，您需要新增
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
指令碼來安裝 Tuist 並執行所需的指令，例如`tuist generate` ：

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
Use an
<LocalizedLink href="/guides/server/authentication#account-tokens">account
token</LocalizedLink> by setting the `TUIST_TOKEN` environment variable in your
Xcode Cloud workflow settings.
<!-- -->
:::

### CircleCI{#circleci}

在 [CircleCI](https://circleci.com) 上，您可以使用
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC 驗證
</LocalizedLink> 來進行安全、無密碼的驗證：

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
Before using OIDC authentication, you need to
<LocalizedLink href="/guides/integrations/gitforge/github">connect your GitHub
repository</LocalizedLink> to your Tuist project. CircleCI OIDC tokens include
your connected GitHub repository, which Tuist uses to authorize access to your
projects. Alternatively, you can use an
<LocalizedLink href="/guides/server/authentication#account-tokens">account
token</LocalizedLink> with the `TUIST_TOKEN` environment variable.
<!-- -->
:::

### Bitrise{#bitrise}

在 [Bitrise](https://bitrise.io) 上，您可以使用
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC 驗證
</LocalizedLink> 來進行安全、無密碼的驗證：

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
Before using OIDC authentication, you need to
<LocalizedLink href="/guides/integrations/gitforge/github">connect your GitHub
repository</LocalizedLink> to your Tuist project. Bitrise OIDC tokens include
your connected GitHub repository, which Tuist uses to authorize access to your
projects. Alternatively, you can use an
<LocalizedLink href="/guides/server/authentication#account-tokens">account
token</LocalizedLink> with the `TUIST_TOKEN` environment variable.
<!-- -->
:::

### 編碼魔術{#codemagic}

在 [Codemagic](https://codemagic.io) 中，您可以在工作流程中增加額外的步驟來安裝 Tuist：

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
Create an
<LocalizedLink href="/guides/server/authentication#account-tokens">account
token</LocalizedLink> and add it as a secret environment variable named
`TUIST_TOKEN`.
<!-- -->
:::
