---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 지속적 통합(CI) {#continuous-integration-ci}

지속적 통합](https://en.wikipedia.org/wiki/Continuous_integration) 워크플로에서 Tuist 명령을
실행하려면 CI 환경에 설치해야 합니다.

인증은 선택 사항이지만 <LocalizedLink href="/guides/features/cache">cache</LocalizedLink>와
같은 서버 측 기능을 사용하려는 경우 필수입니다.

다음 섹션에서는 다양한 CI 플랫폼에서 이 작업을 수행하는 방법에 대한 예를 제공합니다.

## 예제 {#example}

### GitHub 작업 {#github-actions}

GitHub 작업](https://docs.github.com/en/actions)에서
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
인증</LocalizedLink>을 사용하여 안전하고 비밀 없는 인증을 할 수 있습니다:

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
여러 환경에 걸쳐 Tuist 버전을 고정하려면 Tuist 프로젝트에서 `mise use --pin` 을 사용하는 것이 좋습니다. 이 명령은
Tuist의 버전이 포함된 `.tool-versions` 파일을 생성합니다.
<!-- -->
:::

### Xcode 클라우드 {#xcode-cloud}

Xcode 프로젝트를 소스로 사용하는 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)에서
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
스크립트를 추가하여 Tuist를 설치하고 필요한 명령(예: `tuist generate`)을 실행해야 합니다:

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

### CircleCI {#circleci}

CircleCI](https://circleci.com)에서는
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
인증</LocalizedLink>을 사용하여 비밀 없는 안전한 인증을 할 수 있습니다:

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

### Bitrise {#bitrise}

Bitrise](https://bitrise.io)에서는
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC
인증</LocalizedLink>을 사용하여 비밀 없는 안전한 인증을 할 수 있습니다:

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

### 코드매직 {#codemagic}

코드매직](https://codemagic.io)에서 워크플로에 추가 단계를 추가하여 Tuist를 설치할 수 있습니다:

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
