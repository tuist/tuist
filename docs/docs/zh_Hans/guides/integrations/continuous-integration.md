---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 持续集成 (CI){#continuous-integration-ci}

要在 [持续集成](https://en.wikipedia.org/wiki/Continuous_integration) 工作流程中运行 Tuist
命令，需要在 CI 环境中安装它。

身份验证是可选的，但如果要使用<LocalizedLink href="/guides/features/cache">缓存</LocalizedLink>等服务器端功能，则必须进行身份验证。

以下各节将举例说明如何在不同的 CI 平台上实现这一功能。

## 实例{#examples}

### GitHub 操作{#github-actions}

在[GitHub
操作](https://docs.github.com/en/actions)中，您可以使用<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC 身份验证</LocalizedLink>进行安全的无秘身份验证：

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
在使用 OIDC 身份验证之前，您需要 <LocalizedLink href="/guides/integrations/gitforge/github"> 将 GitHub 仓库</LocalizedLink>连接到 Tuist 项目。要使用 OIDC，需要`permissions: id-token:
write` 。或者，你也可以使用带有`TUIST_TOKEN` secret 的
<LocalizedLink href="/guides/server/authentication#project-tokens">项目令牌</LocalizedLink>。
<!-- -->
:::

::: tip
<!-- -->
我们建议在 Tuist 项目中使用`mise use --pin` 来固定跨环境的 Tuist 版本。该命令将创建一个`.tool-versions`
文件，其中包含 Tuist 的版本。
<!-- -->
:::

### Xcode 云{#xcode-cloud}

在使用 Xcode 项目作为真实源的 [Xcode Cloud](https://developer.apple.com/xcode-cloud/)
中，您需要添加一个
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
脚本来安装 Tuist 并运行所需的命令，例如`tuist generate` ：

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
通过在 Xcode Cloud 工作流设置中设置`TUIST_TOKEN` 环境变量，使用
<LocalizedLink href="/guides/server/authentication#project-tokens"> 项目令牌</LocalizedLink>。
<!-- -->
:::

### CircleCI{#circleci}

在 [CircleCI](https://circleci.com) 上，您可以使用
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC 身份验证</LocalizedLink>进行安全的无秘身份验证：

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
在使用 OIDC 身份验证之前，您需要 <LocalizedLink href="/guides/integrations/gitforge/github"> 将 GitHub 仓库</LocalizedLink>连接到 Tuist 项目。CircleCI OIDC 令牌包含已连接的 GitHub 仓库，Tuist
会使用它来授权对项目的访问。或者，你也可以使用`TUIST_TOKEN` 环境变量来获取
<LocalizedLink href="/guides/server/authentication#project-tokens">项目令牌</LocalizedLink>。
<!-- -->
:::

### Bitrise{#bitrise}

在 [Bitrise](https://bitrise.io) 上，您可以使用
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC 身份验证</LocalizedLink>进行安全的无秘身份验证：

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
在使用 OIDC 身份验证之前，您需要 <LocalizedLink href="/guides/integrations/gitforge/github"> 将 GitHub 仓库</LocalizedLink>连接到 Tuist 项目。Bitrise OIDC 令牌包含已连接的 GitHub 仓库，Tuist
会使用它来授权对项目的访问。或者，你也可以使用`TUIST_TOKEN` 环境变量来获取
<LocalizedLink href="/guides/server/authentication#project-tokens">项目令牌</LocalizedLink>。
<!-- -->
:::

### Codemagic{#codemagic}

在 [Codemagic](https://codemagic.io) 中，您可以在工作流程中添加一个额外步骤来安装 Tuist：

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
创建 <LocalizedLink href="/guides/server/authentication#project-tokens"> 项目令牌</LocalizedLink>，并将其添加为秘密环境变量，命名为`TUIST_TOKEN` 。
<!-- -->
:::
