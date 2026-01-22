---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# 継続的インテグレーション (CI){#continuous-integration-ci}

[継続的インテグレーション](https://en.wikipedia.org/wiki/Continuous_integration) ワークフローで
Tuist コマンドを実行するには、CI 環境にインストールする必要があります。

認証は任意ですが、<LocalizedLink href="/guides/features/cache">キャッシュ</LocalizedLink>などのサーバーサイド機能を利用する場合は必須です。

以下のセクションでは、異なるCIプラットフォームでの実施例を示します。

## 例{#example}

### GitHub Actions{#github-actions}

[GitHub
Actions](https://docs.github.com/en/actions)では、安全でシークレットレスな認証を実現する<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC認証</LocalizedLink>を利用できます：

コードグループ
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
OIDC認証を使用する前に、<LocalizedLink href="/guides/integrations/gitforge/github">GitHubリポジトリ</LocalizedLink>をTuistプロジェクトに接続する必要があります。OIDCを機能させるには、`権限:
id-token: write` が必要です。あるいは、`TUIST_TOKEN`
のシークレットを使用した<LocalizedLink href="/guides/server/authentication#account-tokens">アカウントトークン</LocalizedLink>を利用できます。
<!-- -->
:::

::: チップ
<!-- -->
Tuistプロジェクトでは、環境を跨いでTuistのバージョンを固定するために、`mise use --pin`
の使用を推奨します。このコマンドは`.tool-versions` ファイルを作成し、Tuistのバージョンを格納します。
<!-- -->
:::

### Xcode Cloud{#xcode-cloud}

Xcodeプロジェクトを信頼できる情報源として使用する[Xcode
Cloud](https://developer.apple.com/xcode-cloud/)では、Tuistをインストールし必要なコマンド（例：`tuist
generate`
）を実行するために、[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)スクリプトを追加する必要があります。

コードグループ

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
`Xcode Cloudワークフロー設定で、環境変数`TUIST_TOKEN`（`` `）を設定し、`<LocalizedLink
href="/guides/server/authentication#account-tokens">account
token</LocalizedLink>`を使用してください。
<!-- -->
:::

### CircleCI{#circleci}

[CircleCI](https://circleci.com)では、安全でシークレットレスな認証を実現する<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC認証</LocalizedLink>を利用できます：

コードグループ
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
OIDC認証を使用する前に、<LocalizedLink href="/guides/integrations/gitforge/github">GitHubリポジトリ</LocalizedLink>をTuistプロジェクトに接続する必要があります。CircleCIのOIDCトークンには接続済みのGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを認証します。または、環境変数`TUIST_TOKEN`（``
`）で指定する`の<LocalizedLink href="/guides/server/authentication#account-tokens">アカウントトークン</LocalizedLink>を使用することも可能です。
<!-- -->
:::

### Bitrise{#bitrise}

[Bitrise](https://bitrise.io)では、安全でシークレットレスな認証を実現する<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC認証</LocalizedLink>を利用できます：

コードグループ
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
`OIDC認証を使用する前に、<LocalizedLink
href="/guides/integrations/gitforge/github">GitHubリポジトリ</LocalizedLink>をTuistプロジェクトに接続する必要があります。BitriseのOIDCトークンには接続済みのGitHubリポジトリが含まれており、Tuistはこれを使用してプロジェクトへのアクセスを認証します。または、環境変数`TUIST_TOKEN`（``
`）で指定する<LocalizedLink href="/guides/server/authentication#account-tokens">アカウントトークン</LocalizedLink>を使用することも可能です。
<!-- -->
:::

### Codemagic{#codemagic}

[Codemagic](https://codemagic.io)では、ワークフローに追加ステップを加えてTuistをインストールできます：

コードグループ
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
<LocalizedLink href="/guides/server/authentication#account-tokens">アカウントトークン</LocalizedLink>を作成し、`TUIST_TOKEN`
という名前のシークレット環境変数として追加してください。
<!-- -->
:::
