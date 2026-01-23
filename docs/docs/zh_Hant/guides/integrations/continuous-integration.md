---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 持續整合 (CI){#continuous-integration-ci}

要在您的[持續整合](https://en.wikipedia.org/wiki/Continuous_integration)工作流程中執行 Tuist
指令，您需要在 CI 環境中安裝此工具。

驗證為可選項目，但若需使用伺服器端功能（如
<LocalizedLink href="/guides/features/cache">快取</LocalizedLink>）則必須進行驗證。

以下各節將提供在不同 CI 平台上執行此操作的範例。

## 範例{#examples}

### GitHub Actions{#github-actions}

在 [GitHub Actions](https://docs.github.com/en/actions) 中，可使用
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
驗證</LocalizedLink> 實現安全且無密鑰的驗證：

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
在使用 OIDC 驗證前，您需先 <LocalizedLink href="/guides/integrations/gitforge/github">將
GitHub 儲存庫</LocalizedLink> 連結至您的 Tuist 專案。需具備以下權限才能啟用 OIDC：`權限：id-token: write`
。您亦可使用
<LocalizedLink href="/guides/server/authentication#account-tokens">帳戶令牌</LocalizedLink>，其密鑰為`TUIST_TOKEN`
。
<!-- -->
:::

::: tip
<!-- -->
我們建議在 Tuist 專案中使用 ``` 並搭配 `--pin` 參數執行 `` `，以在不同環境中固定 Tuist 版本。此指令將建立 ``` 目錄下的
`.tool-versions` 檔案（路徑為 `` `），該檔案將儲存 Tuist 的版本資訊。
<!-- -->
:::

### Xcode Cloud{#xcode-cloud}

在以 Xcode 專案作為資料來源的 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)
中，您需新增
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
腳本以安裝 Tuist 並執行所需指令，例如：`tuist generate`

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
請透過在 Xcode Cloud 工作流程設定中設定環境變數`TUIST_TOKEN` ，使用
<LocalizedLink href="/guides/server/authentication#account-tokens">帳戶代幣</LocalizedLink>。
<!-- -->
:::

### CircleCI{#circleci}

在 [CircleCI](https://circleci.com) 上，您可使用
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
認證</LocalizedLink> 實現安全且無密鑰的認證：

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
在使用 OIDC 驗證前，您需先 <LocalizedLink href="/guides/integrations/gitforge/github">將
GitHub 儲存庫</LocalizedLink> 連結至您的 Tuist 專案。CircleCI 的 OIDC 憑證會包含您已連結的 GitHub
儲存庫，Tuist 將以此驗證您對專案的存取權限。您亦可改用
<LocalizedLink href="/guides/server/authentication#account-tokens">帳戶憑證</LocalizedLink>，並透過環境變數設定：`TUIST_TOKEN`
<!-- -->
:::

### Bitrise{#bitrise}

在 [Bitrise](https://bitrise.io) 上，您可使用
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
認證</LocalizedLink> 實現安全且無密鑰的認證：

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
在使用 OIDC 驗證前，您需先 <LocalizedLink href="/guides/integrations/gitforge/github">將
GitHub 儲存庫</LocalizedLink> 連結至 Tuist 專案。Bitrise OIDC 憑證會包含您已連結的 GitHub 儲存庫，Tuist
將以此授權存取您的專案。您亦可使用
<LocalizedLink href="/guides/server/authentication#account-tokens">帳戶憑證</LocalizedLink>，並透過環境變數`TUIST_TOKEN`
設定。
<!-- -->
:::

### Codemagic{#codemagic}

在 [Codemagic](https://codemagic.io) 中，您可為工作流程新增安裝 Tuist 的步驟：

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
建立一個
<LocalizedLink href="/guides/server/authentication#account-tokens">帳戶令牌</LocalizedLink>，並將其新增為名為`TUIST_TOKEN
的機密環境變數` 。
<!-- -->
:::
