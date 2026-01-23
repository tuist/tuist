---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 持续集成（CI）{#continuous-integration-ci}

要在[持续集成](https://en.wikipedia.org/wiki/Continuous_integration)工作流中运行Tuist命令，您需要在CI环境中安装该工具。

身份验证为可选操作，但若需使用服务器端功能（如<LocalizedLink href="/guides/features/cache">缓存</LocalizedLink>），则必须进行验证。

以下各节将提供在不同CI平台上实现此操作的示例。

## 示例{#example}

### GitHub Actions{#github-actions}

在[GitHub
Actions](https://docs.github.com/en/actions)上，可使用<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC认证</LocalizedLink>实现安全无密钥认证：

代码组
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
在使用 OIDC 认证前，您需要 <LocalizedLink href="/guides/integrations/gitforge/github">将
GitHub 仓库</LocalizedLink>连接至 Tuist 项目。需授予`权限：id-token: write` 才能使 OIDC
正常运作。您也可使用
<LocalizedLink href="/guides/server/authentication#account-tokens">账户令牌</LocalizedLink>，其密钥为`TUIST_TOKEN`
。
<!-- -->
:::

::: tip
<!-- -->
建议在Tuist项目中使用`mise use --pin` 命令，以在不同环境中固定Tuist版本。该命令将创建`
目录下的.tool-versions文件（路径为` ），其中包含Tuist的版本信息。
<!-- -->
:::

### Xcode Cloud{#xcode-cloud}

在[Xcode
Cloud](https://developer.apple.com/xcode-cloud/)中（其以Xcode项目作为权威数据源），您需要添加[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)脚本以安装Tuist并执行所需命令，例如：`tuist
generate`:

代码组

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
在 Xcode Cloud 工作流设置中，通过设置环境变量`TUIST_TOKEN` 使用
<LocalizedLink href="/guides/server/authentication#account-tokens">账户令牌</LocalizedLink>。
<!-- -->
:::

### CircleCI{#circleci}

在[CircleCI](https://circleci.com)平台上，可使用<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC认证</LocalizedLink>实现安全无密认证：

代码组
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
在使用OIDC认证前，您需要<LocalizedLink href="/guides/integrations/gitforge/github">将GitHub仓库</LocalizedLink>连接至Tuist项目。CircleCI
OIDC令牌包含已连接的GitHub仓库信息，Tuist将据此授权访问您的项目。您也可通过环境变量`设置<LocalizedLink
href="/guides/server/authentication#account-tokens">账户令牌</LocalizedLink>（格式为TUIST_TOKEN`
）。
<!-- -->
:::

### Bitrise{#bitrise}

在[Bitrise](https://bitrise.io)平台上，可使用<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC认证</LocalizedLink>实现安全无密认证：

代码组
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
在使用OIDC认证前，您需要<LocalizedLink href="/guides/integrations/gitforge/github">将GitHub仓库</LocalizedLink>连接至Tuist项目。Bitrise
OIDC令牌包含已连接的GitHub仓库信息，Tuist将据此授权访问您的项目。您也可通过环境变量`设置<LocalizedLink
href="/guides/server/authentication#account-tokens">账户令牌</LocalizedLink>（值为TUIST_TOKEN），或使用`
实现。
<!-- -->
:::

### Codemagic{#codemagic}

在 [Codemagic](https://codemagic.io) 中，您可在工作流中添加额外步骤来安装 Tuist：

代码组
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
创建一个<LocalizedLink href="/guides/server/authentication#account-tokens">账户令牌</LocalizedLink>，并将其作为名为`的环境变量添加：TUIST_TOKEN`
。
<!-- -->
:::
